import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuantivitaAccount {
  const QuantivitaAccount({
    required this.accountId,
    required this.syncToken,
    required this.isAppleLinked,
  });

  final String accountId;
  final String syncToken;
  final bool isAppleLinked;
}

class AccountService {
  static const _appleUserIdentifierKey = 'apple_user_identifier';
  static const _accountIdKey = 'quantivita_account_id';
  static const _syncTokenKey = 'quantivita_sync_token';

  Future<QuantivitaAccount?> loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final accountId = prefs.getString(_accountIdKey);
    final syncToken = prefs.getString(_syncTokenKey);
    if (accountId == null || syncToken == null) return null;

    return QuantivitaAccount(
      accountId: accountId,
      syncToken: syncToken,
      isAppleLinked: prefs.getString(_appleUserIdentifierKey) != null,
    );
  }

  Future<QuantivitaAccount> linkAppleUser(String appleUserIdentifier) async {
    final prefs = await SharedPreferences.getInstance();
    final accountId = _accountIdForAppleUser(appleUserIdentifier);
    final syncToken = prefs.getString(_syncTokenKey) ?? _newSyncToken();

    await prefs.setString(_appleUserIdentifierKey, appleUserIdentifier);
    await prefs.setString(_accountIdKey, accountId);
    await prefs.setString(_syncTokenKey, syncToken);

    return QuantivitaAccount(
      accountId: accountId,
      syncToken: syncToken,
      isAppleLinked: true,
    );
  }

  Future<QuantivitaAccount> ensureLocalAccount() async {
    final existing = await loadAccount();
    if (existing != null) return existing;

    final prefs = await SharedPreferences.getInstance();
    final syncToken = _newSyncToken();
    final accountId = 'qv_local_${_hash(syncToken).substring(0, 18)}';
    await prefs.setString(_accountIdKey, accountId);
    await prefs.setString(_syncTokenKey, syncToken);

    return QuantivitaAccount(
      accountId: accountId,
      syncToken: syncToken,
      isAppleLinked: false,
    );
  }

  String _accountIdForAppleUser(String appleUserIdentifier) {
    return 'qv_${_hash(appleUserIdentifier).substring(0, 24)}';
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  String _newSyncToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
