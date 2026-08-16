/// Runtime configuration.
///
/// Pass values at build time via --dart-define:
///   flutter build ios \
///     --dart-define=API_BASE_URL=https://your-replit-domain.replit.dev/api \
///     --dart-define=CLERK_FRONTEND_API_DOMAIN=your-app.clerk.accounts.dev \
///     --dart-define=NFC_HMAC_SECRET=some-secret-key
class AppConfig {
  AppConfig._();

  /// Base URL of the Beer Mile backend API (no trailing slash).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://change-me.replit.dev/api',
  );

  /// Clerk Frontend API domain, e.g. "your-app.clerk.accounts.dev".
  static const String clerkFrontendApiDomain = String.fromEnvironment(
    'CLERK_FRONTEND_API_DOMAIN',
    defaultValue: 'change-me.clerk.accounts.dev',
  );

  /// HMAC secret shared with the backend for signing NFC tag payloads.
  static const String nfcHmacSecret = String.fromEnvironment(
    'NFC_HMAC_SECRET',
    defaultValue: 'change-me-before-production',
  );

  /// Clerk hosted sign-in URL (opens in WebView).
  static String get clerkSignInUrl =>
      'https://$clerkFrontendApiDomain/sign-in?redirect_url=${Uri.encodeComponent('beermile://auth-callback')}';

  /// Number of lap log records to batch per sync request.
  static const int lapLogBatchSize = 50;

  /// Laps required to finish a Beer Mile.
  static const int lapsPerMile = 4;
}
