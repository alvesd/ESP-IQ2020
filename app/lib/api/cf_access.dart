// Remote HTTPS/SSE + optional Cloudflare Access configuration for IQ2020 Spa.
// LAN-only devices (empty remoteUrl) never use remote URLs or attach build-time Access tokens.

const String kDefaultRemoteUrl = String.fromEnvironment('IQ2020_REMOTE_URL');
const String kDefaultCfAccessClientId = String.fromEnvironment('IQ2020_CF_ACCESS_CLIENT_ID');
const String kDefaultCfAccessClientSecret = String.fromEnvironment('IQ2020_CF_ACCESS_CLIENT_SECRET');

const String kCfAccessBlockedMessage =
    'Blocked by Cloudflare Access. Add or check the Service Token (Client ID & Secret) in Edit hot tub.';

String normalizeRemoteUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (!s.contains('://')) s = 'https://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

class CfAccessConfig {
  final String remoteUrl;
  final String clientId;
  final String clientSecret;

  const CfAccessConfig({
    this.remoteUrl = '',
    this.clientId = '',
    this.clientSecret = '',
  });

  bool get hasRemoteUrl => remoteUrl.isNotEmpty;
  bool get hasCredentials => clientId.isNotEmpty && clientSecret.isNotEmpty;

  Map<String, String> get headers => hasCredentials
      ? {
          'CF-Access-Client-Id': clientId,
          'CF-Access-Client-Secret': clientSecret,
        }
      : const {};

  /// Resolves the effective remote config for a device.
  ///
  /// When [remoteUrl] is empty, returns an empty config so LAN-only devices stay strictly local
  /// even when build-time defaults are compiled into the binary. Build-time Access credentials are
  /// only used as a fallback when the device's configured [remoteUrl] matches [defaultRemoteUrl].
  factory CfAccessConfig.resolve({
    String? remoteUrl,
    String? clientId,
    String? clientSecret,
    String defaultRemoteUrl = kDefaultRemoteUrl,
    String defaultClientId = kDefaultCfAccessClientId,
    String defaultClientSecret = kDefaultCfAccessClientSecret,
  }) {
    final url = normalizeRemoteUrl(remoteUrl ?? '');
    if (url.isEmpty) return const CfAccessConfig();

    final savedId = (clientId ?? '').trim();
    final savedSecret = (clientSecret ?? '').trim();
    if (savedId.isNotEmpty && savedSecret.isNotEmpty) {
      return CfAccessConfig(remoteUrl: url, clientId: savedId, clientSecret: savedSecret);
    }

    final normDefaultUrl = normalizeRemoteUrl(defaultRemoteUrl);
    if (normDefaultUrl.isNotEmpty &&
        url == normDefaultUrl &&
        defaultClientId.trim().isNotEmpty &&
        defaultClientSecret.trim().isNotEmpty) {
      return CfAccessConfig(
        remoteUrl: url,
        clientId: defaultClientId.trim(),
        clientSecret: defaultClientSecret.trim(),
      );
    }

    return CfAccessConfig(remoteUrl: url);
  }
}

bool isCfAccessLoginUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  return lower.contains('cloudflareaccess.com') || lower.contains('/cdn-cgi/access/login');
}

bool isCfAccessBlockedResponse({
  required int statusCode,
  String? locationHeader,
  String? contentType,
  String? bodyPrefix,
}) {
  if (statusCode >= 300 && statusCode < 400 && isCfAccessLoginUrl(locationHeader)) {
    return true;
  }
  if (statusCode == 401 || statusCode == 403 || statusCode == 200) {
    final ct = (contentType ?? '').toLowerCase();
    final body = (bodyPrefix ?? '').toLowerCase();
    if ((ct.contains('text/html') || body.contains('<html')) &&
        (body.contains('cloudflareaccess.com') ||
            body.contains('/cdn-cgi/access/login') ||
            body.contains('cloudflare access'))) {
      return true;
    }
  }
  return false;
}
