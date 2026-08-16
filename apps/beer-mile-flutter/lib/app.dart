import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'providers/auth_providers.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/runner/event_browse_screen.dart';
import 'screens/runner/event_detail_screen.dart';
import 'screens/runner/profile_screen.dart';
import 'screens/runner/leaderboard_screen.dart';
import 'screens/host/host_console_screen.dart';
import 'screens/host/event_form_screen.dart';
import 'screens/host/registrations_screen.dart';
import 'screens/host/tag_provisioning_screen.dart';
import 'screens/scanner/scanner_mode_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/platform_settings_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/sign-in',
    redirect: (context, state) {
      final isSignedIn = authState.valueOrNull != null;
      final role = authState.valueOrNull?.role;
      final isOnSignIn = state.matchedLocation == '/sign-in';

      if (!isSignedIn && !isOnSignIn) return '/sign-in';
      if (isSignedIn && isOnSignIn) {
        if (role == 'super_admin') return '/admin';
        if (role == 'host') return '/host';
        return '/runner/events';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: '/runner/events',
        builder: (_, __) => const EventBrowseScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => EventDetailScreen(
              eventId: int.parse(state.pathParameters['id']!),
            ),
            routes: [
              GoRoute(
                path: 'leaderboard',
                builder: (_, state) => LeaderboardScreen(
                  eventId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/runner/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/host',
        builder: (_, __) => const HostConsoleScreen(),
        routes: [
          GoRoute(
            path: 'events/new',
            builder: (_, __) => const EventFormScreen(),
          ),
          GoRoute(
            path: 'events/:id/edit',
            builder: (_, state) => EventFormScreen(
              eventId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: 'events/:id/registrations',
            builder: (_, state) => RegistrationsScreen(
              eventId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: 'events/:id/tags',
            builder: (_, state) => TagProvisioningScreen(
              eventId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: 'events/:id/scanner',
            builder: (_, state) => ScannerModeScreen(
              eventId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'platform-settings',
            builder: (_, __) => const PlatformSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

class BeerMileApp extends ConsumerWidget {
  const BeerMileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'Beer Mile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
