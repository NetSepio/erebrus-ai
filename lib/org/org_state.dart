import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/wallet_auth_controller.dart';
import 'ai_org.dart';
import 'org_client.dart';
import 'shared_model.dart';

/// Reactive org list, selected org, and shared models for the signed-in user.
class OrgState extends ChangeNotifier {
  OrgState({
    required this._auth,
    OrgClient? client,
  }) : _client = client ?? OrgClient() {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final WalletAuthController _auth;
  final OrgClient _client;

  List<AiOrg> orgs = [];
  AiOrg? selectedOrg;
  List<SharedModel> orgModels = [];
  bool isLoading = false;
  String? error;

  bool get isAuthenticated => _auth.isAuthenticated;
  String? get _token => _auth.bearerToken;

  void _onAuthChanged() {
    if (!_auth.isAuthenticated) {
      orgs = [];
      selectedOrg = null;
      orgModels = [];
      notifyListeners();
      return;
    }
    unawaited(refreshOrgs());
  }

  Future<void> refreshOrgs() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      orgs = await _client.fetchOrganizations(token);
      if (selectedOrg == null && orgs.isNotEmpty) {
        selectedOrg = orgs.first;
      }
      await refreshOrgModels();
    } on OrgException catch (e) {
      error = e.message;
      orgs = [];
      selectedOrg = null;
      orgModels = [];
    } catch (e) {
      error = e.toString();
      orgs = [];
      selectedOrg = null;
      orgModels = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectOrg(AiOrg org) async {
    selectedOrg = org;
    notifyListeners();
    await refreshOrgModels();
  }

  Future<void> refreshOrgModels() async {
    final token = _token;
    final org = selectedOrg;
    if (token == null || token.isEmpty || org == null) {
      orgModels = [];
      notifyListeners();
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      orgModels = await _client.fetchOrgModels(org.id, token);
    } on OrgException catch (e) {
      error = e.message;
      orgModels = [];
    } catch (e) {
      error = e.toString();
      orgModels = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sharePersona(String personaId) async {
    final token = _token;
    final org = selectedOrg;
    if (token == null || token.isEmpty || org == null) return;
    try {
      await _client.sharePersona(orgId: org.id, personaId: personaId, bearerToken: token);
    } on OrgException catch (e) {
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
