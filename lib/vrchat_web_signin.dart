import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'vrchat_api.dart';

/// Experimental VRChat-owned WebView session handoff. Never contacts ModSuite.
class VrchatWebSignIn extends StatefulWidget {
  const VrchatWebSignIn({super.key});
  @override
  State<VrchatWebSignIn> createState() => _VrchatWebSignInState();
}

class _VrchatWebSignInState extends State<VrchatWebSignIn> {
  static const _cookies = MethodChannel('modsuite/vrchat_web_cookies');
  late final WebViewController controller;
  String status = 'Sign in on VRChat, then tap Connect website session.';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri?.scheme != 'https') return NavigationDecision.prevent;
          // OAuth identity providers need to load in the login view.
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('https://vrchat.com/home/login'));
  }

  String? cookieValue(List<dynamic> headers, String name) {
    for (final header in headers) {
      for (final entry in header.toString().split(';')) {
        final part = entry.trim();
        if (part.startsWith('$name=')) return part.substring(name.length + 1);
      }
    }
    return null;
  }

  Future<void> connect() async {
    setState(() { busy = true; status = 'Checking website session with VRChat…'; });
    try {
      final headers = await _cookies.invokeListMethod<String>('readVrchatCookies') ?? [];
      final auth = cookieValue(headers, 'auth');
      final twoFactor = cookieValue(headers, 'twoFactorAuth') ?? '';
      if (auth == null || auth.isEmpty) {
        throw StateError('No VRChat auth cookie is available to the Android WebView. This sign-in method may not share an API session.');
      }
      await VrchatApi.connect(auth, twoFactor);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => status = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VRChat website sign-in')),
    body: Column(children: [
      const Padding(
        padding: EdgeInsets.all(10),
        child: Text('Experimental: Google may block embedded browsers. The website may not expose a usable VRChat API session. No VRChat cookies go to ModSuite.'),
      ),
      Expanded(child: WebViewWidget(controller: controller)),
      Padding(padding: const EdgeInsets.all(10), child: Text(status)),
      Padding(
        padding: const EdgeInsets.all(10),
        child: FilledButton(
          onPressed: busy ? null : connect,
          child: Text(busy ? 'Checking…' : 'Connect website session'),
        ),
      ),
    ]),
  );
}
