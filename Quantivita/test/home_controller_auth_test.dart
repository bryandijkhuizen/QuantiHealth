import 'package:flutter_test/flutter_test.dart';
import 'package:quantivita/controllers/home_controller.dart';
import 'package:quantivita/services/apple_auth_service.dart';
import 'package:quantivita/services/health_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Apple sign-in lands on permissions without opening Health', () async {
    SharedPreferences.setMockInitialValues({});
    final health = _FakeHealthPermissionService();
    final controller = HomeController(
      appleAuthService: _FakeAppleAuthService(),
      healthPermissionService: health,
    );
    await Future<void>.delayed(Duration.zero);

    await controller.signInWithApple();

    expect(controller.stage, AppStage.permissions);
    expect(controller.isAppleAccountConnected, isTrue);
    expect(health.authorizationRequests, 0);
  });
}

class _FakeAppleAuthService extends AppleAuthService {
  @override
  Future<AppleAuthResult> signIn() async {
    return const AppleAuthResult(
      status: AppleAuthStatus.signedIn,
      userIdentifier: 'apple-user',
    );
  }
}

class _FakeHealthPermissionService extends HealthPermissionService {
  var authorizationRequests = 0;

  @override
  Future<HealthPermissionResult> requestAuthorization() async {
    authorizationRequests++;
    return const HealthPermissionResult(
      status: HealthPermissionStatus.denied,
      message: 'Denied',
    );
  }
}
