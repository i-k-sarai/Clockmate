import 'dart:convert';

/// A logged-in Keka session captured from the WebView. No password is stored.
class KekaSession {
  const KekaSession({
    required this.host,
    required this.token,
    this.expiresAt,
    this.name,
    this.email,
  });

  /// Builds a session from a bearer token, reading expiry and identity from
  /// its JWT claims. Returns null if the token isn't a readable JWT.
  static KekaSession? fromToken(String host, String token) {
    final claims = decodeJwtPayload(token);
    if (claims == null) return null;
    final exp = claims['exp'];
    return KekaSession(
      host: host,
      token: token,
      expiresAt: exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
          : null,
      name: _nameFrom(claims),
      email: _emailFrom(claims),
    );
  }

  /// Company host, e.g. acme.keka.com.
  final String host;
  final String token;

  /// Null when the token carries no expiry; it is then refreshed only on 401.
  final DateTime? expiresAt;
  final String? name;
  final String? email;

  String get displayName => name ?? email ?? host;

  bool expiresSoon(DateTime now, {Duration margin = const Duration(minutes: 2)}) {
    final expiry = expiresAt;
    return expiry != null && !now.add(margin).isBefore(expiry);
  }

  /// Keeps the previous identity if the new token lacks those claims.
  KekaSession withToken(String newToken) {
    final fresh = fromToken(host, newToken);
    return KekaSession(
      host: host,
      token: newToken,
      expiresAt: fresh?.expiresAt,
      name: fresh?.name ?? name,
      email: fresh?.email ?? email,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'token': token,
        'expiresAt': expiresAt?.toIso8601String(),
        'name': name,
        'email': email,
      };

  factory KekaSession.fromJson(Map<String, dynamic> json) => KekaSession(
        host: json['host'] as String,
        token: json['token'] as String,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
        name: json['name'] as String?,
        email: json['email'] as String?,
      );
}

/// Company tenants live on `<company>.keka.com`; these subdomains are Keka's own.
const _kekaServiceSubdomains = {'app', 'login', 'www', 'accounts', 'auth', 'api', 'cdn'};

bool isCompanyHost(String host) {
  if (!host.endsWith('.keka.com')) return false;
  final sub = host.substring(0, host.length - '.keka.com'.length);
  return sub.isNotEmpty && !sub.contains('.') && !_kekaServiceSubdomains.contains(sub);
}

Map<String, dynamic>? decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final json = jsonDecode(payload);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}

String? _nameFrom(Map<String, dynamic> claims) {
  final name = claims['name'];
  if (name is String && name.trim().isNotEmpty) return name.trim();
  final full = [claims['given_name'], claims['family_name']]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  return full.isEmpty ? null : full;
}

String? _emailFrom(Map<String, dynamic> claims) {
  for (final key in ['email', 'preferred_username', 'unique_name']) {
    final value = claims[key];
    if (value is String && value.contains('@')) return value;
  }
  return null;
}
