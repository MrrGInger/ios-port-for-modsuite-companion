import 'dart:async';
import 'companion_api.dart';
import 'vrchat_api.dart';

class GroupInviteTracker {
  final void Function() onChange;
  GroupInviteTracker(this.onChange);
  Timer? _timer;
  bool _busy=false;
  String status='Waiting for pairing and VRChat login';
  int today=0, week=0;
  static const group='grp_7112d2b5-7a61-4ce0-8d1e-2285a4f37421';

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => check());
    check();
  }
  Future<void> check() async {
    if (_busy || !VrchatApi.connected) return;
    _busy=true;
    try {
      final token=await CompanionApi.storage.read(key: CompanionApi.tokenKey);
      if (token == null || token.isEmpty) return;
      final stats=await CompanionApi.inviteRequest(token,'GET','stats');
      today=(stats['today'] as num?)?.toInt() ?? 0;
      week=(stats['week'] as num?)?.toInt() ?? 0;
      final pending=await CompanionApi.inviteRequest(token,'GET','pending');
      final requests=(pending['requests'] as List?) ?? [];
      for (final item in requests) {
        final id=(item as Map)['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final claim=await CompanionApi.inviteRequest(token,'POST','claim',{'id':id});
        String state='unknown';
        String error='';
        try {
          // Verify the VRChat account matches the paired ModSuite staff ID.
          final me=await VrchatApi.currentUser();
          final profile=await CompanionApi.profile(token);
          if (me['id']?.toString()!=profile['user_id']?.toString()) {
            state='failed'; error='VRChat account does not match paired moderator';
          } else if (claim['group_id']?.toString()!=group) {
            state='failed'; error='Wrong group';
          } else {
            await VrchatApi.inviteToGroup(group,claim['target_id'].toString());
            state='succeeded';
          }
        } catch (e) {
          // Report only the HTTP status or exception type, never raw API responses.
          final message = e.toString();
          final httpStatus = RegExp(r'VRChat HTTP (\d{3})').firstMatch(message)?.group(1);
          state = 'unknown';
          error = httpStatus == null
              ? 'VRChat request error: ${e.runtimeType}'
              : 'VRChat HTTP $httpStatus';
        }
        await CompanionApi.inviteRequest(token,'POST','result',{'id':id,'state':state,'error':error});
      }
      final refreshed=await CompanionApi.inviteRequest(token,'GET','stats');
      today=(refreshed['today'] as num?)?.toInt() ?? 0;
      week=(refreshed['week'] as num?)?.toInt() ?? 0;
      status='Updated';
    } catch (_) { status='Invite sync unavailable; will check again'; }
    finally { _busy=false; onChange(); }
  }
  void dispose(){_timer?.cancel();}
}

