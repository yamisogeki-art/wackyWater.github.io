/// App Web URL & Deep Linking configuration.
const String appWebUrl = 'https://musical-arithmetic-dbdd3b.netlify.app';
const String appRedirectUrl = 'https://musical-arithmetic-dbdd3b.netlify.app/auth/callback';

/// Build-time Environment Configuration: 'dev', 'staging', or 'production'.
/// Set via `--dart-define=API_ENVIRONMENT=production`
const String apiEnvironment = String.fromEnvironment(
  'API_ENVIRONMENT',
  defaultValue: 'production',
);

/// Default base URL presets based on environment
const String _prodBaseUrl = 'https://wackysmart-forecast.onrender.com';
const String _stagingBaseUrl = 'https://api-staging.wackysmart.app';
const String _devBaseUrl = 'http://10.0.2.2:8000';

/// Resolves the API Base URL based on environment or custom `--dart-define=API_BASE_URL=...`
String get resolvedApiBaseUrl {
  const customUrl = String.fromEnvironment('API_BASE_URL');
  if (customUrl.isNotEmpty) return customUrl;

  switch (apiEnvironment.toLowerCase()) {
    case 'dev':
    case 'development':
      return _devBaseUrl;
    case 'staging':
      return _stagingBaseUrl;
    case 'production':
    case 'prod':
    default:
      return _prodBaseUrl;
  }
}

/// FastAPI backend base URL for demand forecasting.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: _prodBaseUrl,
);

/// API Key header authentication for calling the FastAPI forecast endpoint.
/// Set via `--dart-define=FORECAST_API_KEY=your_key`
const String forecastApiKey = String.fromEnvironment(
  'FORECAST_API_KEY',
  defaultValue: 'wackysmart_secret_key_2025',
);

/// Drivers sign in with a short username (e.g. `driver1`) on the driver
/// login screen. Supabase auth needs an email, so a username without an
/// "@" is turned into `<username>@<this domain>`.
const String driverUsernameEmailDomain = 'driver.wackysmart.app';
