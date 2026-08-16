import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/loading_indicator.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _showWebView = false;
  bool _loading = false;
  late WebViewController _controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_showWebView) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _showWebView = false),
          ),
          title: const Text('Sign In'),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const LoadingIndicator(message: 'Completing sign in…'),
          ],
        ),
      );
    }

    if (_loading) {
      return const Scaffold(
        body: LoadingIndicator(message: 'Signing in…'),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.sports_bar, size: 80, color: cs.primary),
              const SizedBox(height: 16),
              Text('Beer Mile',
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              Text('Multi-tenant race timing',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign In / Register'),
              ),
              const SizedBox(height: 12),
              Text(
                'Supports Google, Apple, and Email/Password',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _openSignIn() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterTokenChannel',
        onMessageReceived: (msg) => _handleToken(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          // Inject a poller that detects when Clerk session is established
          // and forwards the JWT back to Flutter.
          await _controller.runJavaScript('''
            (function startClerkPoller() {
              var attempts = 0;
              var interval = setInterval(function() {
                attempts++;
                if (attempts > 120) { clearInterval(interval); return; }
                if (window.Clerk && window.Clerk.session) {
                  window.Clerk.session.getToken().then(function(t) {
                    if (t) {
                      clearInterval(interval);
                      FlutterTokenChannel.postMessage(t);
                    }
                  }).catch(function(){});
                }
              }, 1000);
            })();
          ''');
        },
        onNavigationRequest: (req) {
          if (req.url.startsWith('beermile://auth-callback')) {
            final uri = Uri.tryParse(
                req.url.replaceFirst('beermile://', 'https://'));
            final token = uri?.queryParameters['token'] ??
                uri?.fragment
                    .split('token=')
                    .elementAtOrNull(1)
                    ?.split('&')
                    .first;
            if (token != null && token.isNotEmpty) {
              _handleToken(token);
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(AppConfig.clerkSignInUrl));

    setState(() => _showWebView = true);
  }

  Future<void> _handleToken(String token) async {
    if (token.isEmpty) return;
    setState(() {
      _loading = true;
      _showWebView = false;
    });

    await ref.read(authStateProvider.notifier).signInWithToken(token);

    // authStateProvider.notifier.signInWithToken wraps errors in AsyncValue —
    // check the resulting state rather than relying on a rethrown exception.
    if (!mounted) return;
    final authState = ref.read(authStateProvider);
    if (authState.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign in failed: ${authState.error}'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _openSignIn,
          ),
        ),
      );
      setState(() => _loading = false);
    }
    // On success the GoRouter redirect picks up the non-null user and navigates.
  }
}
