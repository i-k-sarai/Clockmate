import 'dart:convert';

import 'package:clockmate/app/format.dart';
import 'package:clockmate/features/keka/keka_api.dart';
import 'package:clockmate/features/keka/keka_endpoints.dart';
import 'package:clockmate/features/keka/keka_session.dart';
import 'package:clockmate/features/keka/keka_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

String jwt(Map<String, Object?> claims) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

void main() {
  final now = DateTime(2026, 11, 2, 9, 0);
  int epoch(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  group('KekaSession', () {
    test('reads expiry and identity from the JWT', () {
      final token = jwt({
        'exp': epoch(now.add(const Duration(hours: 1))),
        'given_name': 'Asha',
        'family_name': 'Rao',
        'preferred_username': 'asha@acme.com',
      });
      final session = KekaSession.fromToken('acme.keka.com', token)!;
      expect(session.expiresAt, now.add(const Duration(hours: 1)));
      expect(session.name, 'Asha Rao');
      expect(session.email, 'asha@acme.com');
      expect(session.expiresSoon(now), isFalse);
      expect(session.expiresSoon(now.add(const Duration(minutes: 59))), isTrue);
    });

    test('rejects tokens that are not JWTs', () {
      expect(KekaSession.fromToken('acme.keka.com', 'not-a-jwt'), isNull);
    });

    test('survives a JSON round trip', () {
      final session = KekaSession(
        host: 'acme.keka.com',
        token: 't',
        expiresAt: now,
        name: 'Asha',
        email: 'asha@acme.com',
      );
      final restored = KekaSession.fromJson(session.toJson());
      expect(restored.host, session.host);
      expect(restored.expiresAt, now);
      expect(restored.email, 'asha@acme.com');
    });

    test('withToken keeps identity when the new token lacks it', () {
      const session = KekaSession(host: 'acme.keka.com', token: 'old', name: 'Asha');
      final renewed = session.withToken(jwt({'exp': epoch(now)}));
      expect(renewed.name, 'Asha');
      expect(renewed.expiresAt, now);
    });

    test('only company subdomains count as company hosts', () {
      expect(isCompanyHost('acme.keka.com'), isTrue);
      expect(isCompanyHost('app.keka.com'), isFalse);
      expect(isCompanyHost('login.keka.com'), isFalse);
      expect(isCompanyHost('a.b.keka.com'), isFalse);
      expect(isCompanyHost('acme.keka.com.evil.io'), isFalse);
    });
  });

  group('KekaSessionService', () {
    late KekaSession? stored;
    late List<String?> refreshResults;
    late int refreshCalls;

    KekaSessionService service() => KekaSessionService(
          load: () async => stored,
          save: (s) async => stored = s,
          refresh: (_) async {
            refreshCalls++;
            return refreshResults.removeAt(0);
          },
          now: () => now,
        );

    final fresh = jwt({'exp': epoch(now.add(const Duration(hours: 1)))});
    final renewed = jwt({'exp': epoch(now.add(const Duration(hours: 2)))});

    setUp(() {
      refreshResults = [];
      refreshCalls = 0;
    });

    test('uses a fresh token without refreshing', () async {
      stored = KekaSession.fromToken('acme.keka.com', fresh);
      final used = await service().run((s) async => s.token);
      expect(used, fresh);
      expect(refreshCalls, 0);
    });

    test('refreshes a token that is about to expire', () async {
      stored = KekaSession.fromToken('acme.keka.com', jwt({'exp': epoch(now.add(const Duration(minutes: 1)))}));
      refreshResults = [renewed];
      final used = await service().run((s) async => s.token);
      expect(used, renewed);
      expect(stored!.token, renewed);
    });

    test('refreshes and retries once on 401', () async {
      stored = KekaSession.fromToken('acme.keka.com', fresh);
      refreshResults = [renewed];
      final used = await service().run((s) async {
        if (s.token == fresh) throw const KekaUnauthorized();
        return s.token;
      });
      expect(used, renewed);
      expect(refreshCalls, 1);
    });

    test('reports an expired session when refresh fails', () async {
      stored = KekaSession.fromToken('acme.keka.com', fresh);
      refreshResults = [null];
      expect(
        service().run<void>((s) async => throw const KekaUnauthorized()),
        throwsA(isA<KekaSessionExpired>()),
      );
    });

    test('reports an expired session when not connected', () async {
      stored = null;
      expect(service().run((s) async => 1), throwsA(isA<KekaSessionExpired>()));
    });

    group('ensureValid', () {
      final expiring = jwt({'exp': epoch(now.add(const Duration(minutes: 1)))});

      test('returns a fresh session without refreshing', () async {
        stored = KekaSession.fromToken('acme.keka.com', fresh);
        expect((await service().ensureValid()).token, fresh);
        expect(refreshCalls, 0);
      });

      test('silently renews a session that is about to expire', () async {
        stored = KekaSession.fromToken('acme.keka.com', expiring);
        refreshResults = [renewed];
        expect((await service().ensureValid()).token, renewed);
        expect(stored!.token, renewed);
      });

      test('reports expiry when the saved login is gone too', () async {
        stored = KekaSession.fromToken('acme.keka.com', expiring);
        refreshResults = [null];
        await expectLater(service().ensureValid(), throwsA(isA<KekaSessionExpired>()));
      });

      test('reports expiry when not connected', () async {
        stored = null;
        await expectLater(service().ensureValid(), throwsA(isA<KekaSessionExpired>()));
      });
    });
  });

  group('parseStatus', () {
    test('latest punch today decides the status', () {
      final json = {
        'data': [
          {
            'timeEntries': [
              {'punchStatus': 0, 'actualTimestamp': DateTime(2026, 11, 2, 8, 1).toIso8601String()},
              {'punchStatus': 1, 'actualTimestamp': DateTime(2026, 11, 2, 8, 30).toIso8601String()},
              {'punchStatus': 0, 'actualTimestamp': DateTime(2026, 11, 2, 8, 45).toIso8601String()},
            ],
          },
          {
            'timeEntries': [
              {'punchStatus': 1, 'actualTimestamp': DateTime(2026, 11, 1, 18).toIso8601String()},
            ],
          },
        ],
      };
      final status = KekaEndpoints.parseStatus(json, now);
      expect(status.clockedIn, isTrue);
      expect(status.since, DateTime(2026, 11, 2, 8, 45));
    });

    test('no punches today means not clocked in', () {
      expect(KekaEndpoints.parseStatus({'data': []}, now).clockedIn, isFalse);
    });
  });

  test('daysSummary', () {
    expect(daysSummary({1, 2, 3, 4, 5}), 'Mon–Fri');
    expect(daysSummary({1, 2, 3, 4, 5, 6, 7}), 'Every day');
    expect(daysSummary({6, 7}), 'Weekends');
    expect(daysSummary({2, 3, 4}), 'Tue–Thu');
    expect(daysSummary({1, 3, 5}), 'Mon, Wed, Fri');
  });
}
