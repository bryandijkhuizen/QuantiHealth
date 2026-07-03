import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum AppleAuthStatus { signedIn, canceled, unavailable, failed }

class AppleAuthResult {
  const AppleAuthResult({
    required this.status,
    this.userIdentifier,
    this.message,
  });

  final AppleAuthStatus status;
  final String? userIdentifier;
  final String? message;
}

class AppleAuthService {
  Future<AppleAuthResult> signIn() async {
    try {
      final isAvailable = await SignInWithApple.isAvailable().timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (!isAvailable) {
        return const AppleAuthResult(
          status: AppleAuthStatus.unavailable,
          message:
              'Apple Sign In is not available on this device or build. Check the entitlement and Apple Developer capability.',
        );
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
      ).timeout(const Duration(seconds: 45));

      final userIdentifier = credential.userIdentifier;
      if (userIdentifier == null || userIdentifier.isEmpty) {
        return const AppleAuthResult(
          status: AppleAuthStatus.failed,
          message: 'Apple Sign In did not return a user identifier.',
        );
      }
      return AppleAuthResult(
        status: AppleAuthStatus.signedIn,
        userIdentifier: userIdentifier,
      );
    } on TimeoutException {
      return const AppleAuthResult(
        status: AppleAuthStatus.failed,
        message:
            'Apple Sign In timed out. Check your network, Apple ID prompt, and the Sign in with Apple capability for this build.',
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return const AppleAuthResult(status: AppleAuthStatus.canceled);
      }

      return AppleAuthResult(
        status: AppleAuthStatus.failed,
        message: 'Apple Sign In failed: ${error.code.name}.',
      );
    } on PlatformException catch (error) {
      return AppleAuthResult(
        status: AppleAuthStatus.unavailable,
        message:
            error.message ??
            'Enable Sign in with Apple in Xcode and Apple Developer.',
      );
    }
  }
}
