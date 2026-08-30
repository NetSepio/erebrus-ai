import 'package:erebrus_ai/auth/auth_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth URL logging drops all query parameters and fragments', () {
    const token = 'secret-paseto';
    const state = 'secret-state';
    final redacted = redactedAuthUrlForLog(
      'https://erebrus.io/auth?token=$token&future_secret=value&state=$state#code',
    );

    expect(redacted, 'https://erebrus.io/auth');
    expect(redacted, isNot(contains(token)));
    expect(redacted, isNot(contains(state)));
    expect(redacted, isNot(contains('future_secret')));
  });

  test('custom-scheme callbacks keep only scheme, authority, and path', () {
    expect(
      redactedAuthUrlForLog('erebrusai://auth/callback?token=secret'),
      'erebrusai://auth/callback',
    );
  });
}
