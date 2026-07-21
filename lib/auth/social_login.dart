import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'runtime_config.dart';

/// Thin wrappers around the native OIDC providers. Each returns the provider's
/// id_token (a JWT the gateway verifies) or `null` when the user cancels.
/// Callers gate these on availability so an unconfigured provider is never
/// invoked.

/// Whether native Google sign-in can run: a server client id is configured and
/// the platform is supported (Android / iOS).
bool get googleSignInSupported =>
    RuntimeConfig.hasGoogleSignIn && (Platform.isAndroid || Platform.isIOS);

/// Whether Apple sign-in can run: native on iOS/macOS, or a configured Services
/// id elsewhere.
Future<bool> appleSignInSupported() async {
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return await SignInWithApple.isAvailable();
    } catch (_) {
      return false;
    }
  }
  return RuntimeConfig.appleServiceId.isNotEmpty;
}

/// Runs the Google sign-in sheet and returns an id_token, or null if cancelled.
Future<String?> googleIdToken() async {
  final google = GoogleSignIn(
    serverClientId: RuntimeConfig.googleServerClientId.isNotEmpty
        ? RuntimeConfig.googleServerClientId
        : null,
    scopes: const ['email'],
  );
  final account = await google.signIn();
  if (account == null) return null;
  final auth = await account.authentication;
  final token = auth.idToken;
  if (token == null || token.isEmpty) {
    throw const SocialLoginException('Google did not return an identity token');
  }
  return token;
}

/// Runs Apple sign-in and returns every value the gateway validates.
Future<AppleLoginCredential?> appleCredential() async {
  final serviceId = RuntimeConfig.appleServiceId;
  final useWebRelay = !(Platform.isIOS || Platform.isMacOS);
  final nonce = generateNonce();
  final state = 'ai.${generateNonce()}';
  try {
    final cred = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: useWebRelay && serviceId.isNotEmpty
          ? WebAuthenticationOptions(
              clientId: serviceId,
              redirectUri: Uri.parse(RuntimeConfig.appleRedirectUri),
            )
          : null,
      nonce: nonce,
      state: state,
    );
    final token = cred.identityToken;
    if (token == null || token.isEmpty) {
      throw const SocialLoginException(
        'Apple did not return an identity token',
      );
    }
    if (cred.state != state) {
      throw const SocialLoginException(
        'Apple sign-in state mismatch — please try again',
      );
    }
    return AppleLoginCredential(
      identityToken: token,
      authorizationCode: cred.authorizationCode,
      nonce: nonce,
      state: state,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) return null;
    throw SocialLoginException(
      e.message.isEmpty ? 'Apple sign-in failed' : e.message,
    );
  }
}

class AppleLoginCredential {
  const AppleLoginCredential({
    required this.identityToken,
    required this.authorizationCode,
    required this.nonce,
    required this.state,
  });

  final String identityToken;
  final String authorizationCode;
  final String nonce;
  final String state;
}

/// Best-effort sign-out from the Google session.
Future<void> googleSignOut() async {
  try {
    await GoogleSignIn().signOut();
  } catch (e) {
    debugPrint('[social] google signOut: $e');
  }
}

class SocialLoginException implements Exception {
  const SocialLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}
