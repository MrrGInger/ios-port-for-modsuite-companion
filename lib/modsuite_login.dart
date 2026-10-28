import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens the existing ModSuite login in an isolated in-app browser.
/// Authentication cookies belong to the WebView and are not exported to Dart.
class ModSuiteLoginPage extends StatefulWidget {
  const ModSuiteLoginPage({super.key, this.approvalUrl});
  final String? approvalUrl;

  @override
  State<ModSuiteLoginPage> createState() => _ModSuiteLoginPageState();
}

class _ModSuiteLoginPageState extends State<ModSuiteLoginPage> {
  static final Uri loginUri = Uri.parse(
    'https://tcostaffmodtool.tcostaffmodtools.com/login/modsuite',
  );
  late final WebViewController controller;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() { loading = true; error = null; }); },
        onPageFinished: (_) { if (mounted) setState(() => loading = false); },
        onWebResourceError: (failure) {
          if (failure.isForMainFrame == true && mounted) {
            setState(() { loading = false; error = failure.description; });
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || uri.scheme != 'https' ||
              uri.host != loginUri.host) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(widget.approvalUrl == null ? loginUri : Uri.parse(widget.approvalUrl!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ModSuite Login'), actions: [
      IconButton(
        tooltip: 'Reload login',
        onPressed: () => controller.loadRequest(loginUri),
        icon: const Icon(Icons.refresh),
      ),
    ]),
    body: Column(children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Padding(padding: const EdgeInsets.all(12),
          child: Text('Unable to load ModSuite: $error')),
      Expanded(child: WebViewWidget(controller: controller)),
    ]),
  );
}
