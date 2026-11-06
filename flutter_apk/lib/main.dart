import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// The web app is served from http://localhost:<port>. Keep the port fixed:
// browser storage (your accounting data) is tied to this origin.
const int kPort = 8089;
final InAppLocalhostServer server =
    InAppLocalhostServer(documentRoot: 'assets/www', port: kPort);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await server.start();
  runApp(const ShopBooksApp());
}

class ShopBooksApp extends StatelessWidget {
  const ShopBooksApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ShopBooks',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E), useMaterial3: true),
        home: const WebShell(),
      );
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});
  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  InAppWebViewController? _c;
  final _auth = LocalAuthentication();

  void _register(InAppWebViewController c) {
    // Save a file (backup JSON / CSV) via the system share sheet.
    c.addJavaScriptHandler(
      handlerName: 'saveFile',
      callback: (args) async {
        final name = args[0] as String;
        final data = args[2] as String;
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsString(data);
        await Share.shareXFiles([XFile(f.path)], text: name);
        return true;
      },
    );
    // Print / save as PDF.
    c.addJavaScriptHandler(
      handlerName: 'printHtml',
      callback: (args) async {
        final html = args[0] as String;
        await Printing.layoutPdf(
          onLayout: (format) => Printing.convertHtml(format: format, html: html),
        );
        return true;
      },
    );
    // Share text (invoices -> WhatsApp etc.).
    c.addJavaScriptHandler(
      handlerName: 'shareText',
      callback: (args) async {
        await Share.share(args[0] as String);
        return true;
      },
    );
    // Open links such as WhatsApp reminders.
    c.addJavaScriptHandler(
      handlerName: 'openUrl',
      callback: (args) async {
        await launchUrl(Uri.parse(args[0] as String), mode: LaunchMode.externalApplication);
        return true;
      },
    );
    // Fingerprint / face / device screen-lock check.
    c.addJavaScriptHandler(
      handlerName: 'biometric',
      callback: (args) async {
        try {
          if (!await _auth.isDeviceSupported()) return false;
          return await _auth.authenticate(
            localizedReason: 'Unlock ShopBooks',
            options: const AuthenticationOptions(stickyAuth: true),
          );
        } catch (_) {
          return false;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Close any open sheet in the web app first, otherwise leave the app.
        final closed = await _c?.evaluateJavascript(
          source:
              "(function(){var m=document.getElementById('modal');if(m&&m.classList.contains('on')){closeM();return true}return false})()",
        );
        if (closed != true) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F766E),
        body: SafeArea(
          bottom: false,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('http://localhost:$kPort/index.html')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              supportZoom: false,
              useHybridComposition: true,
              mediaPlaybackRequiresUserGesture: true,
            ),
            onWebViewCreated: (c) {
              _c = c;
              _register(c);
            },
          ),
        ),
      ),
    );
  }
}
