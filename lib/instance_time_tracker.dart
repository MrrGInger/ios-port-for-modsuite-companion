import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'vrchat_api.dart';
import 'companion_api.dart';

/// Conservative, foreground-only VRChat group instance tracker.
/// A minute is credited only after two consecutive matching VRChat location
/// confirmations; unknown locations, errors, and transitions are not credited.
class InstanceTimeTracker {
  static const group = 'grp_7112d2b5-7a61-4ce0-8d1e-2285a4f37421';
  static const _historyKey = 'modsuite_instance_history_v1';
  static const _pendingKey = 'modsuite_session_pending_v2';
  static const _storage = FlutterSecureStorage();
  static final _random = Random.secure();
  final void Function() onChange;
  InstanceTimeTracker(this.onChange);
  Timer? _poll;
  Timer? _clock;
  bool _busy = false;
  bool enabled = false;
  String? instance;
  String? status;
  DateTime? entered;
  DateTime? lastConfirmed;
  int creditedSeconds = 0;
  int currentSeconds = 0;
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> pending = [];

  static bool belongsToGroup(String? location) {
    if (location == null) return false;
    // VRChat location strings encode group instances as ~group(grp_...).
    return RegExp(r'~group\(' + group + r'\)(?:~|$)').hasMatch(location);
  }

  Future<void> restore() async {
    try {
      history = (jsonDecode(await _storage.read(key: _historyKey) ?? '[]') as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();
      pending = (jsonDecode(await _storage.read(key: _pendingKey) ?? '[]') as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();
    } catch (_) { status = 'Could not load saved time history'; }
    onChange();
  }

  Future<void> start() async {
    if (enabled) return;
    enabled = true;
    status = 'Checking your VRChat location';
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => onChange());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => check());
    onChange();
    await check();
  }

  Future<void> stop() async {
    enabled = false;
    _poll?.cancel(); _clock?.cancel();
    await _endSession();
    status = 'Tracking stopped';
    onChange();
  }

  Future<void> _endSession() async {
    if (instance != null && entered != null && currentSeconds > 0) {
      history.insert(0, {
        'date': entered!.toIso8601String(),
        'ended': (lastConfirmed ?? DateTime.now().toUtc()).toIso8601String(),
        'duration_seconds': currentSeconds,
        'qualification': 'Pending verification',
        'credited_seconds': 0,
      });
      if (currentSeconds > 0) {
        final end = lastConfirmed ?? DateTime.now().toUtc();
        final id = '${end.microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
        history.first['session_id'] = id;
        pending.add({'session_id': id, 'started_at': entered!.millisecondsSinceEpoch ~/ 1000,
          'ended_at': end.millisecondsSinceEpoch ~/ 1000, 'duration_seconds': currentSeconds});
        await _storage.write(key: _pendingKey, value: jsonEncode(pending));
      }
      if (history.length > 300) history = history.sublist(0, 300);
      await _storage.write(key: _historyKey, value: jsonEncode(history));
    }
    instance = null; entered = null; lastConfirmed = null; currentSeconds = 0;
  }

  Future<void> check() async {
    if (!enabled || _busy) return;
    _busy = true;
    try {
      final user = await VrchatApi.ownLocation();
      final location = user['location']?.toString();
      final now = DateTime.now().toUtc();
      final valid = belongsToGroup(location);
      if (!valid) {
        await _endSession();
        status = 'Not in a verified group instance — not counting';
      } else if (instance != location) {
        await _endSession();
        instance = location;
        entered = now;
        lastConfirmed = now;
        status = 'Group instance confirmed — tracking';
      } else {
        final gap = now.difference(lastConfirmed!).inSeconds;
        // Do not count time across long suspensions or lost connectivity.
        if (gap > 0 && gap <= 45) {
          currentSeconds += gap;

        }
        lastConfirmed = now;
        status = 'Group instance confirmed — tracking';
      }
      await flush();
    } catch (e) {
      // A failed API read must never cause unchecked time to accumulate.
      await _endSession();
      status = 'Location unavailable — timer paused: $e';
    } finally { _busy = false; onChange(); }
  }

  Future<void> flush() async {
    final token = await CompanionApi.storage.read(key: CompanionApi.tokenKey);
    if (token == null || token.isEmpty) return;
    while (pending.isNotEmpty) {
      try {
        final receipt = pending.first;
        final result = await CompanionApi.submitSession(token, receipt);
        final match = history.where((h) => h['session_id'] == receipt['session_id']);
        if (match.isNotEmpty) {
          match.first['qualification'] = result['qualified'] == true ? 'Met Requirements' : 'Not Met Requirements';
          match.first['credited_seconds'] = (result['credited_seconds'] as num?)?.toInt() ?? 0;
          match.first['counts'] = result['counts'];
          creditedSeconds += (result['credited_seconds'] as num?)?.toInt() ?? 0;
          await _storage.write(key: _historyKey, value: jsonEncode(history));
        }
        pending.removeAt(0);
        await _storage.write(key: _pendingKey, value: jsonEncode(pending));
      } catch (_) { break; }
    }
    onChange();
  }

  void dispose() { _poll?.cancel(); _clock?.cancel(); }
}
