import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'expiry_store.dart';
import 'group_service.dart';
import 'message_service.dart';
import 'supabase_service.dart';

/// Un message vient de disparaître (l'écran concerné doit le retirer).
class ExpiryEvent {
  final String convKey;
  final dynamic id;

  const ExpiryEvent(this.convKey, this.id);
}

class _Entry {
  final dynamic id;

  /// Échéance en millisecondes (epoch). Chaque message a une échéance
  /// 20 s APRÈS celle du précédent : c'est la file FIFO.
  final int at;

  _Entry(this.id, this.at);
}

class _Conv {
  final String key;
  final bool isGroup;
  final String other; // numéro du contact, ou id du groupe
  final List<_Entry> queue = [];
  Timer? timer;

  _Conv(this.key, this.isGroup, this.other);
}

/// Service GLOBAL de disparition des messages reçus.
///
/// - Ouvrir une conversation = lire. Dès l'ouverture, les messages reçus
///   entrent dans une file FIFO par conversation : 20 s pour le premier,
///   puis 20 s pour le suivant une fois le premier parti, etc.
/// - La file tourne TOUTE SEULE : fermer la conversation, changer d'écran ou
///   perdre la connexion ne l'arrête pas. Elle ne dépend d'aucun écran.
/// - Les échéances sont enregistrées sur le téléphone : elles survivent à la
///   mise en veille ou à la fermeture de l'application.
/// - La suppression / lecture côté serveur se fait en arrière-plan, avec
///   réessais, sans jamais retarder la file.
class ExpiryService with WidgetsBindingObserver {
  ExpiryService._();

  static final ExpiryService instance = ExpiryService._();

  static const Duration delay = Duration(seconds: 20);

  // Mêmes clés que celles lues par l'onglet des conversations.
  static const String _directPrefix = 'pending_msg_deletes_';
  static const String _groupPrefix = 'pending_group_reads_';

  static String directKey(String me, String other) =>
      '$_directPrefix${me}_$other';

  static String groupKey(String me, String groupId) =>
      '$_groupPrefix${me}_$groupId';

  final Map<String, _Conv> _convs = {};
  final Map<String, RealtimeChannel> _channels = {};
  final Set<String> _gone = {}; // '<convKey>|<id>' disparus (cette session)
  final Set<String> _syncing = {};
  final StreamController<ExpiryEvent> _events =
      StreamController<ExpiryEvent>.broadcast();

  String? _me;
  Future<void>? _starting;
  bool _observing = false;

  Stream<ExpiryEvent> get onExpired => _events.stream;

  String get _queuePrefsKey => 'expiry_queue_$_me';

  // ------------------------------------------------------------------
  // Démarrage (idempotent) : reprend les files et synchronisations
  // laissées en cours lors d'une précédente session.
  // ------------------------------------------------------------------
  Future<void> start(String myPhone) {
    if (_me == myPhone && _starting != null) return _starting!;

    if (_me != null && _me != myPhone) {
      for (final c in _convs.values) {
        c.timer?.cancel();
      }
      _convs.clear();
      _gone.clear();
    }

    _me = myPhone;
    _starting = _doStart(myPhone);

    return _starting!;
  }

  Future<void> _doStart(String me) async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }

    await _loadPersisted(me);
    await _resumePendingSyncs(me);

    for (final c in _convs.values.toList()) {
      _schedule(c);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'app, on recalcule les échéances (les minuteurs ont pu
    // être suspendus) et on relance les synchronisations en attente.
    if (state == AppLifecycleState.resumed && _me != null) {
      for (final c in _convs.values.toList()) {
        _schedule(c);
      }
      _resumePendingSyncs(_me!);
    }
  }

  Future<void> _loadPersisted(String me) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('expiry_queue_$me');

      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);

      if (decoded is! Map) return;

      decoded.forEach((key, value) {
        if (value is! Map) return;

        final conv = _convs.putIfAbsent(
          key.toString(),
          () => _Conv(
            key.toString(),
            value['kind'] == 'group',
            value['other'].toString(),
          ),
        );

        final entries = value['entries'];

        if (entries is List) {
          for (final e in entries) {
            if (e is! Map) continue;

            final sid = e['id'].toString();

            if (conv.queue.any((x) => x.id.toString() == sid)) continue;
            if (_gone.contains('${conv.key}|$sid')) continue;

            conv.queue.add(_Entry(e['id'], (e['at'] as num).toInt()));
          }
        }

        conv.queue.sort((a, b) => a.at.compareTo(b.at));
      });
    } catch (e) {
      debugPrint('Erreur lecture des files de disparition: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = <String, dynamic>{};

      for (final c in _convs.values) {
        if (c.queue.isEmpty) continue;

        data[c.key] = {
          'kind': c.isGroup ? 'group' : 'direct',
          'other': c.other,
          'entries': c.queue.map((e) => {'id': e.id, 'at': e.at}).toList(),
        };
      }

      if (data.isEmpty) {
        await prefs.remove(_queuePrefsKey);
      } else {
        await prefs.setString(_queuePrefsKey, jsonEncode(data));
      }
    } catch (_) {}
  }

  // Relance la synchronisation serveur de tous les messages déjà disparus
  // de l'écran mais pas encore confirmés (toutes conversations).
  Future<void> _resumePendingSyncs(String me) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final directStart = '$_directPrefix${me}_';
      final groupStart = '$_groupPrefix${me}_';

      for (final key in prefs.getKeys()) {
        final isDirect = key.startsWith(directStart);
        final isGroup = key.startsWith(groupStart);

        if (!isDirect && !isGroup) continue;

        final other = key.substring(
          isDirect ? directStart.length : groupStart.length,
        );

        for (final id in prefs.getStringList(key) ?? const <String>[]) {
          unawaited(_sync(key, isGroup, other, id));
        }
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // API utilisée par les écrans
  // ------------------------------------------------------------------

  /// Les messages [ids] viennent d'être ouverts (affichés) : ils entrent
  /// dans la file de disparition. Sans effet s'ils y sont déjà ou déjà partis.
  Future<void> enqueue({
    required String me,
    required bool isGroup,
    required String other,
    required List<dynamic> ids,
  }) async {
    await start(me);

    final key = isGroup ? groupKey(me, other) : directKey(me, other);
    final conv = _convs.putIfAbsent(key, () => _Conv(key, isGroup, other));

    final pending = await ExpiryStore.load(key);

    bool changed = false;

    for (final id in ids) {
      if (id == null) continue;

      final sid = id.toString();

      if (_gone.contains('$key|$sid')) continue;
      if (pending.contains(sid)) continue;
      if (conv.queue.any((e) => e.id.toString() == sid)) continue;

      final now = DateTime.now().millisecondsSinceEpoch;
      final base = conv.queue.isEmpty ? now : max(now, conv.queue.last.at);

      conv.queue.add(_Entry(id, base + delay.inMilliseconds));
      changed = true;
    }

    if (changed) {
      _schedule(conv);
      await _persist();
    }
  }

  /// Le message a disparu ailleurs (supprimé côté serveur) : on l'enlève de
  /// la file sans décaler les autres.
  void drop(String convKey, List<dynamic> ids) {
    final conv = _convs[convKey];

    for (final id in ids) {
      _gone.add('$convKey|$id');
      conv?.queue.removeWhere((e) => e.id.toString() == id.toString());
    }

    if (conv != null) {
      _schedule(conv);
      _persist();
    }
  }

  /// Vrai si ce message a déjà disparu chez moi (il ne doit pas réapparaître).
  bool isExpired(String convKey, dynamic id) => _gone.contains('$convKey|$id');

  /// Messages déjà ouverts et en cours de compte à rebours (donc « lus »).
  Set<String> queuedIds(String convKey) {
    final conv = _convs[convKey];

    if (conv == null) return <String>{};

    return conv.queue.map((e) => e.id.toString()).toSet();
  }

  /// Canal temps réel de l'écran ouvert : sert à prévenir l'autre
  /// participant dès la suppression (facultatif).
  void attachChannel(String convKey, RealtimeChannel channel) {
    _channels[convKey] = channel;
  }

  void detachChannel(String convKey, RealtimeChannel channel) {
    if (identical(_channels[convKey], channel)) {
      _channels.remove(convKey);
    }
  }

  // ------------------------------------------------------------------
  // Minuterie (locale, sans réseau)
  // ------------------------------------------------------------------
  void _schedule(_Conv conv) {
    conv.timer?.cancel();
    conv.timer = null;

    if (conv.queue.isEmpty) return;

    final wait = conv.queue.first.at - DateTime.now().millisecondsSinceEpoch;

    conv.timer = Timer(
      Duration(milliseconds: wait > 0 ? wait : 0),
      () => _expireHead(conv),
    );
  }

  void _expireHead(_Conv conv) {
    conv.timer = null;

    if (conv.queue.isEmpty) return;

    final entry = conv.queue.removeAt(0);

    _gone.add('${conv.key}|${entry.id}');

    // 1) Le message disparaît de l'écran, tout de suite.
    _events.add(ExpiryEvent(conv.key, entry.id));

    // 2) Le suivant est déjà programmé (échéance = précédente + 20 s).
    _schedule(conv);

    // 3) Serveur en arrière-plan, sans jamais bloquer la file.
    unawaited(_finish(conv, entry.id));
  }

  Future<void> _finish(_Conv conv, dynamic id) async {
    await ExpiryStore.add(conv.key, id);
    await _persist();
    await _sync(conv.key, conv.isGroup, conv.other, id);
  }

  // ------------------------------------------------------------------
  // Synchronisation serveur (arrière-plan, réessais espacés)
  // ------------------------------------------------------------------
  Future<void> _sync(String key, bool isGroup, String other, dynamic id) async {
    final me = _me;

    if (me == null) return;

    final syncKey = '$key|$id';

    if (!_syncing.add(syncKey)) return;

    int attempt = 0;

    try {
      while (_me == me) {
        bool done = false;
        bool deletedByMe = false;

        try {
          if (isGroup) {
            await GroupService.markMessageRead(
              messageId: id,
              groupId: other,
              memberPhone: me,
              channel: _channels[key],
            );

            done = await _isReadOrGone(me, id);
          } else {
            deletedByMe = await MessageService.deleteMessageById(id);
            done = deletedByMe || await _isGoneFromServer(id);
          }
        } catch (e) {
          debugPrint('Erreur synchronisation disparition: $e');
          done = false;
        }

        if (done) {
          await ExpiryStore.remove(key, id);

          final channel = _channels[key];

          if (!isGroup && deletedByMe && channel != null) {
            await MessageService.broadcastMessagesDeleted(
              channel: channel,
              ids: [id],
            );
          }

          return;
        }

        attempt++;

        final seconds = min(5 * (1 << min(attempt - 1, 4)), 60);

        await Future.delayed(Duration(seconds: seconds));
      }
    } finally {
      _syncing.remove(syncKey);
    }
  }

  Future<bool> _isGoneFromServer(dynamic id) async {
    try {
      final row = await SupabaseService.client
          .from('messages')
          .select('id')
          .eq('id', id)
          .maybeSingle();

      return row == null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isReadOrGone(String me, dynamic id) async {
    try {
      final read = await SupabaseService.client
          .from('group_message_reads')
          .select('message_id')
          .eq('message_id', id)
          .eq('member_phone', me)
          .maybeSingle();

      if (read != null) return true;

      final message = await SupabaseService.client
          .from('group_messages')
          .select('id')
          .eq('id', id)
          .maybeSingle();

      return message == null;
    } catch (_) {
      return false;
    }
  }
}
