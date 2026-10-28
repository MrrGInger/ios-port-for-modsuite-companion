import 'group_invite_tracker.dart';
import 'instance_time_tracker.dart';
import 'vrchat_api.dart';
import 'vrchat_web_signin.dart';
import 'companion_api.dart';
import 'modsuite_login.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

void main() => runApp(const ModSuiteApp());

class ModSuiteApp extends StatelessWidget {
  const ModSuiteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ModSuite Companion', debugShowCheckedModeBanner: false,
    theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF4FA3),
    brightness: Brightness.dark,
    surface: const Color(0xFF000000),
  ),
  scaffoldBackgroundColor: const Color(0xFF000000),
  cardColor: const Color(0xFF000000),
  dividerColor: const Color(0xFFFF4FA3),
  useMaterial3: true,
),
    home: const CompanionShell(),
  );
}

class CompanionShell extends StatefulWidget {
  const CompanionShell({super.key});
  @override
  State<CompanionShell> createState() => _CompanionShellState();
}

class _CompanionShellState extends State<CompanionShell> {
  int page = 0;
  late final InstanceTimeTracker timeTracker = InstanceTimeTracker(() {
    if (mounted) setState(() {});
  });
  late final GroupInviteTracker inviteTracker = GroupInviteTracker(() {
    if (mounted) setState(() {});
  });
  Map<String, dynamic>? profile;
  String? pairingStatus;
  bool pairing = false;
  bool vrchatConnected = false;
  bool vrchatBusy = false;
  bool searching = false;
  bool acting = false;
  String? vrchatStatus;
  String? searchStatus;
  String? actionStatus;
  Map<String, dynamic>? vrchatUser;
  List<Map<String, dynamic>> results = [];
  final authCookie = TextEditingController();
  final twoFactorCookie = TextEditingController();
  final groupId = TextEditingController(text: 'grp_7112d2b5-7a61-4ce0-8d1e-2285a4f37421');
  String? selectedUserId;

  @override
  void initState() { super.initState(); restoreProfile(); restoreVrchat(); timeTracker.restore(); inviteTracker.start(); }
  Future<void> restoreProfile() async {
    final token = await CompanionApi.storage.read(key: CompanionApi.tokenKey);
    if (token == null) return;
    try {
      final data = await CompanionApi.profile(token);
      if (mounted) setState(() => profile = data);
    } catch (_) { if (mounted) setState(() => pairingStatus = 'Stored pairing is no longer valid. Pair again.'); }
  }
  Future<void> restoreVrchat() async {
    await VrchatApi.restore();
    if (mounted) setState(() => vrchatConnected = VrchatApi.connected);
    // Restoring credentials does not generate any background VRChat request.
  }

  Future<void> openVrchatSignIn() async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VrchatWebSignIn()),
    );
    if (connected == true) {
      try {
        final user = await VrchatApi.currentUser();
        if (mounted) {
          setState(() {
          vrchatConnected = true;
          vrchatUser = user;
          vrchatStatus = 'VRChat website session connected';
        });
        }
      } catch (e) {
        if (mounted) setState(() => vrchatStatus = 'Session verification failed: $e');
      }
    }
  }

  Future<void> connectVrchat() async {
    setState(() { vrchatBusy = true; vrchatStatus = 'Checking VRChat sessionÃ¢â‚¬Â¦'; });
    try {
      await VrchatApi.connect(authCookie.text, twoFactorCookie.text);
      final user = await VrchatApi.currentUser();
      if (mounted) setState(() { vrchatConnected = true; vrchatUser = user; vrchatStatus = 'Connected to VRChat'; });
      authCookie.clear(); twoFactorCookie.clear();
    } catch (e) {
      if (mounted) setState(() => vrchatStatus = 'VRChat connection failed: $e');
    } finally { if (mounted) setState(() => vrchatBusy = false); }
  }

  Future<void> disconnectVrchat() async {
    await timeTracker.stop();
    await VrchatApi.disconnect();
    if (mounted) setState(() { vrchatConnected = false; vrchatUser = null; results = []; vrchatStatus = 'VRChat disconnected locally.'; });
  }

  Future<void> searchPlayers() async {
    if (!VrchatApi.connected) { setState(() => searchStatus = 'Connect VRChat in Settings first.'); return; }
    setState(() { searching = true; searchStatus = null; results = []; });
    try {
      final found = await VrchatApi.search(player.text);
      if (mounted) setState(() { results = found; searchStatus = '${found.length} player(s) found'; });
    } catch (e) { if (mounted) setState(() => searchStatus = 'Search failed: $e'); }
    finally { if (mounted) setState(() => searching = false); }
  }

  bool get canModerate {
    final permissions = profile?['permissions'];
    return permissions is Map && permissions['file_ban'] == true &&
        permissions['access_modsuite'] == true;
  }

  Future<void> performAction(bool isBan) async {
    if (acting) return;
    final id = VrchatApi.extractUserId(player.text);
    final group = groupId.text.trim();
    final action = isBan ? 'Ban' : 'Unban';
    if (profile == null || !canModerate) {
      setState(() => actionStatus = 'ModSuite does not authorize this staff account for bans.'); return;
    }
    if (!VrchatApi.connected) { setState(() => actionStatus = 'Connect VRChat first.'); return; }
    if (id == null || !RegExp(r'^usr_[0-9a-fA-F-]{36}$').hasMatch(id)) {
      setState(() => actionStatus = 'Select a valid VRChat user ID.'); return;
    }
    if (!RegExp(r'^grp_[0-9a-fA-F-]{36}$').hasMatch(group)) {
      setState(() => actionStatus = 'Enter the VRChat group ID.'); return;
    }
    if (reason.text.trim().isEmpty) {
      setState(() => actionStatus = 'A reason is required for your records.'); return;
    }
    setState(() { acting = true; actionStatus = 'Verifying accountsÃ¢â‚¬Â¦'; });
    try {
      // Recheck staff permissions immediately before every action.
      final token = await CompanionApi.storage.read(key: CompanionApi.tokenKey);
      if (token == null) throw StateError('ModSuite pairing missing');
      final freshProfile = await CompanionApi.profile(token);
      final perms = freshProfile['permissions'];
      if (perms is! Map || perms['file_ban'] != true || perms['access_modsuite'] != true) {
        throw StateError('ModSuite permission denied');
      }
      final vrUser = await VrchatApi.currentUser();
      if (vrUser['id']?.toString() != freshProfile['user_id']?.toString()) {
        throw StateError('VRChat account does not match your paired ModSuite user ID');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('Confirm $action'),
        content: Text('$action $id in $group?\nReason: ${reason.text.trim()}\n\nThis action uses your local VRChat session. This build does NOT automatically file a ModSuite incident or Discord log.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Confirm $action'))],
      ));
      if (confirmed != true) { if (mounted) setState(() => actionStatus = 'Cancelled'); return; }
      if (isBan) { await VrchatApi.ban(group, id); } else { await VrchatApi.unban(group, id); }
      if (mounted) setState(() => actionStatus = '$action succeeded on VRChat. Record the action and reason in ModSuite manually; automatic logging is not integrated.');
    } catch (e) { if (mounted) setState(() => actionStatus = '$action failed: $e'); }
    finally { if (mounted) setState(() => acting = false); }
  }

  Future<void> disconnect() async {
    await CompanionApi.storage.delete(key: CompanionApi.tokenKey);
    if (mounted) setState(() { profile = null; pairingStatus = 'Disconnected locally. Revoke this device key on the website to invalidate it on the server.'; });
  }
  Future<void> startPairing() async {
    if (pairing) return;
    setState(() { pairing = true; pairingStatus = 'Creating pairing requestÃ¢â‚¬Â¦'; });
    try {
      final start = await CompanionApi.post('/api/agent/pair/start', {'client_name': 'ModSuite Companion Android'});
      final code = start['code'] as String;
      final secret = start['secret'] as String;
      final url = start['url'] as String;
      if (!mounted) return;
      setState(() => pairingStatus = 'Pairing code: $code. Sign in if needed, then open approval.');
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModSuiteLoginPage()));
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModSuiteLoginPage(approvalUrl: url)));
      for (var attempt = 0; attempt < 24; attempt++) {
        final result = await CompanionApi.post('/api/agent/pair/poll', {'code': code, 'secret': secret});
        if (result['status'] == 'approved') {
          final token = result['token'] as String;
          final data = await CompanionApi.profile(token);
          await CompanionApi.storage.write(key: CompanionApi.tokenKey, value: token);
          if (mounted) setState(() { profile = data; pairingStatus = 'Device paired successfully.'; page = 0; });
          return;
        }
        await Future.delayed(const Duration(seconds: 3));
      }
      if (mounted) setState(() => pairingStatus = 'Still pending. Start a new pairing if the code expired.');
    } catch (e) {
      if (mounted) setState(() => pairingStatus = 'Pairing failed: $e');
    } finally { if (mounted) setState(() => pairing = false); }
  }

  final server = TextEditingController(text: 'https://tcostaffmodtool.tcostaffmodtools.com');
  final player = TextEditingController();
  final reason = TextEditingController();
  String? validation;
  bool checking = false;
  Future<void> checkConnection() async {
    if (!validServer) {
      setState(() => validation = 'Enter a valid HTTPS server address.');
      return;
    }
    setState(() { checking = true; validation = 'Checking connectionÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦'; });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final base = Uri.parse(server.text.trim());
      final endpoint = base.replace(path: '/healthz', query: null, fragment: null);
      final request = await client.getUrl(endpoint).timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      if (!mounted) return;
      setState(() => validation = response.statusCode == 200
          ? 'Server reachable (health check: HTTP 200). Login is not connected yet.'
          : 'Server responded: HTTP ${response.statusCode}. Login is not connected yet.');
    } on TimeoutException {
      if (mounted) setState(() => validation = 'Connection timed out. Check the address and internet access.');
    } on HandshakeException {
      if (mounted) setState(() => validation = 'HTTPS certificate validation failed.');
    } on SocketException {
      if (mounted) setState(() => validation = 'Cannot reach the server. Check DNS or internet connection.');
    } catch (e) {
      if (mounted) setState(() => validation = 'Connection failed: ${e.runtimeType}.');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => checking = false);
    }
  }
  @override
  void dispose() { inviteTracker.dispose(); timeTracker.dispose(); server.dispose(); player.dispose(); reason.dispose(); authCookie.dispose(); twoFactorCookie.dispose(); groupId.dispose(); super.dispose(); }
  bool get validServer {
    final u = Uri.tryParse(server.text.trim());
    return u != null && u.scheme == 'https' && u.host.isNotEmpty && u.userInfo.isEmpty;
  }
  @override
  Widget build(BuildContext context) {
    final screens = [dashboard(), lookup(), moderation(), times(), settings()];
    return Scaffold(
      appBar: AppBar(
  title: Row(
    children: [
      Image.asset(
        'assets/images/modsuite-logo.png',
        width: 36,
        height: 36,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 10),
      const Text('ModSuite Companion'),
    ],
  ),
),
      body: SafeArea(child: screens[page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page, onDestinationSelected: (i) => setState(() => page = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Players'),
          NavigationDestination(icon: Icon(Icons.gavel_outlined), label: 'Actions'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Tracker'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
  Widget section(List<Widget> items) => ListView(padding: const EdgeInsets.all(18), children: items);
  bool get _accountsReady => profile != null && vrchatConnected;

  Widget _dashboardTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFF4FA3), size: 28),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );

  Widget _dashboardStat(String label, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFF4FA3)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    ),
  );
  Widget dashboard() => section([
    const SizedBox(height: 8),
    const Text('Teen Chillout ModSuite', textAlign: TextAlign.center,
      style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Companion Dashboard', textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFFFF4FA3))),
    const SizedBox(height: 18),
    _dashboardTile(
      icon: Icons.verified_user_outlined,
      title: 'ModSuite Account',
      subtitle: profile == null ? 'Not paired - tap to connect' :
        '${profile!['name'] ?? 'Staff'} | Rank: ${profile!['role'] ?? 'Unknown'}',
      onTap: () => setState(() => page = profile == null ? 0 : 4),
    ),
    if (profile == null)
      FilledButton.icon(
        onPressed: pairing ? null : startPairing,
        icon: const Icon(Icons.link),
        label: Text(pairing ? 'Pairing...' : 'Connect ModSuite Account'),
      ),
    if (pairingStatus != null) Text(pairingStatus!),
    _dashboardTile(
      icon: Icons.link,
      title: 'VRChat Account',
      subtitle: vrchatConnected
        ? (vrchatUser?['displayName']?.toString() ?? 'Connected on this device')
        : 'Not connected - tap to open Settings',
      onTap: () => setState(() => page = 4),
    ),
    const SizedBox(height: 14),
    const Text('Activity overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    if (!_accountsReady)
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Connect both ModSuite and VRChat to view your activity.'),
      ),
    Row(children: [
      Expanded(child: _dashboardStat('Instance time',
        _accountsReady ? _duration(timeTracker.currentSeconds) : '--:--:--', Icons.timer_outlined)),
      Expanded(child: _dashboardStat('Invites today',
        _accountsReady ? '${inviteTracker.today}' : '--', Icons.person_add_alt_outlined)),
    ]),
    Row(children: [
      Expanded(child: _dashboardStat('Invites this week',
        _accountsReady ? '${inviteTracker.week}' : '--', Icons.calendar_today_outlined)),
      Expanded(child: _dashboardStat('Tracking',
        _accountsReady ? (timeTracker.enabled ? 'Active' : 'Stopped') : 'Not ready', Icons.timeline)),
    ]),
    if (_accountsReady) ...[
      const SizedBox(height: 8),
      Text(timeTracker.status ?? 'Time tracker ready'),
      Text(inviteTracker.status),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: inviteTracker.check,
          icon: const Icon(Icons.refresh), label: const Text('Refresh invites')),
        OutlinedButton.icon(onPressed: () => setState(() => page = 3),
          icon: const Icon(Icons.timer), label: const Text('Open tracker')),
      ]),
    ],
    const SizedBox(height: 16),
    const Text('Quick access', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 750 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(width: width, child: _dashboardTile(
          icon: Icons.search, title: 'Players', subtitle: 'Search VRChat users',
          onTap: () => setState(() => page = 1))),
        SizedBox(width: width, child: _dashboardTile(
          icon: Icons.gavel_outlined, title: 'Actions', subtitle: 'Moderation tools',
          onTap: () => setState(() => page = 2))),
        SizedBox(width: width, child: _dashboardTile(
          icon: Icons.timer_outlined, title: 'Tracker', subtitle: 'Time and group invites',
          onTap: () => setState(() => page = 3))),
        SizedBox(width: width, child: _dashboardTile(
          icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Accounts and connections',
          onTap: () => setState(() => page = 4))),
      ]);
    }),
  ]);
  Widget lookup() => section([
    const Text('Player Search', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    TextField(controller: player, decoration: const InputDecoration(labelText: 'Display name, user ID or VRChat profile URL', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: searching ? null : searchPlayers, icon: const Icon(Icons.search), label: Text(searching ? 'SearchingÃ¢â‚¬Â¦' : 'Search VRChat')),
    if (searchStatus != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(searchStatus!)),
    ...results.map((user) => Card(child: ListTile(
      title: Text(user['displayName']?.toString() ?? 'Unknown player'),
      subtitle: Text(user['id']?.toString() ?? ''),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => setState(() { selectedUserId = user['id']?.toString(); player.text = selectedUserId ?? ''; page = 2; }),
    ))),
  ]);
  Widget moderation() => section([
    const Text('Moderation', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    TextField(controller: groupId, decoration: const InputDecoration(labelText: 'VRChat group ID (grp_...)', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    TextField(controller: player, decoration: const InputDecoration(labelText: 'Target VRChat user ID or profile URL', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    TextField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Required reason', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    const Text('Ban and Unban are available. The app checks your ModSuite permissions and matches your VRChat account before each action.'),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: FilledButton(onPressed: acting ? null : () => performAction(true), child: const Text('Ban'))),
      const SizedBox(width: 12),
      Expanded(child: OutlinedButton(onPressed: acting ? null : () => performAction(false), child: const Text('Unban'))),
    ]),
    if (actionStatus != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(actionStatus!)),
    const SizedBox(height: 12),
    const Text('Automatic ModSuite incident/Discord logging is not configured in this build. Record completed actions manually.', style: TextStyle(fontSize: 12)),
  ]);
  Widget times() => section([
    const Text('Group Instance Tracker', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Only verified instances owned by your VRChat group count. Tracking works while this app is open. VRChat locations never go to ModSuite.'),
    const SizedBox(height: 14),
    Card(child: ListTile(
      leading: Icon(timeTracker.instance == null ? Icons.timer_off : Icons.timer),
      title: Text(timeTracker.instance == null ? 'No verified group instance' : 'Group instance active'),
      subtitle: Text(timeTracker.status ?? 'Tracking not started'),
    )),
    Card(child: ListTile(
      title: const Text('Confirmed session time'),
      subtitle: Text(_duration(timeTracker.currentSeconds), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
    )),
    Row(children: [
      Expanded(child: FilledButton(
        onPressed: !vrchatConnected || timeTracker.enabled ? null : timeTracker.start,
        child: const Text('Start tracking'))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton(
        onPressed: timeTracker.enabled ? timeTracker.stop : null,
        child: const Text('Stop tracking'))),
    ]),
    const SizedBox(height: 8),
    OutlinedButton(onPressed: timeTracker.flush, child: Text('Retry pending reports (${timeTracker.pending.length})')),
    const SizedBox(height: 18),
    const Text('Previous sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ...timeTracker.history.map((h) => ListTile(
      title: Text(DateTime.tryParse(h['date']?.toString() ?? '')?.toLocal().toString().split('.').first ?? 'Unknown date'),
      subtitle: Text('${h['qualification'] ?? 'Legacy / Unverified'} â€¢ Credited: ${_duration((h['credited_seconds'] as num?)?.toInt() ?? 0)}'),
      trailing: Text(_duration((h['duration_seconds'] as num?)?.toInt() ?? 0)),
    )),
    const Divider(height: 36),
    const Text('Group Membership Invites', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Card(child: ListTile(title: const Text('Today'), trailing: Text('${inviteTracker.today}'))),
    Card(child: ListTile(title: const Text('This week (Sunâ€“Sat)'), trailing: Text('${inviteTracker.week}'))),
    Text(inviteTracker.status),
    OutlinedButton(onPressed: inviteTracker.check, child: const Text('Refresh invites')),
  ]);

  static String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget settings() => section([
    const Text('Connection settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    TextField(controller: server, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'ModSuite HTTPS address', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    FilledButton(onPressed: checking ? null : checkConnection, child: Text(checking ? 'CheckingÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦' : 'Test server connection')),
    if (validation != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(validation!)),
    const SizedBox(height: 18),
    const Text('ModSuite pairing is saved securely and restored after app restarts. VRChat cookies never go to ModSuite.'),
    const SizedBox(height: 22),
    const Text('VRChat connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text(vrchatConnected ? 'VRChat cookie saved on this device' : 'VRChat not connected'),
    if (!vrchatConnected) ...[
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: openVrchatSignIn,
        icon: const Icon(Icons.open_in_browser),
        label: const Text('Open VRChat sign-in (Google and other providers)'),
      ),
      const SizedBox(height: 8),
      const Text('Experimental in-app VRChat HTTPS login. After signing in, tap Connect website session. Google may reject embedded browsers, and the website session may not work with the VRChat API. Manual cookie login remains available.'),
      const SizedBox(height: 16),
      const Text('Advanced: connect with VRChat session cookies', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: authCookie, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'VRChat auth cookie', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: twoFactorCookie, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'twoFactorAuth cookie (optional)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton(onPressed: vrchatBusy ? null : connectVrchat, child: Text(vrchatBusy ? 'ConnectingÃ¢â‚¬Â¦' : 'Connect VRChat')),
    ] else OutlinedButton(onPressed: disconnectVrchat, child: const Text('Disconnect VRChat (local only)')),
    if (vrchatStatus != null) Text(vrchatStatus!),
    const SizedBox(height: 18),
    if (profile != null) OutlinedButton(onPressed: disconnect, child: const Text('Unpair ModSuite (local only)')),

  ]);
}


