import 'package:erebrus_ai/auth/entitlement_state.dart';
import 'package:erebrus_ai/org/ai_org.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entitlement renders a family-qualified plan label', () {
    final entitlement = EntitlementState.fromJson({
      'entitled': true,
      'status': 'active',
      'plan_id': 'personal.pro',
      'capability_tier': 'pro',
    });

    expect(entitlement.planId, 'personal.pro');
    expect(entitlement.planLabel, 'Personal · Pro');
    expect(entitlement.capabilityTier, 'pro');
  });

  test('organization renders a family-qualified plan label', () {
    final org = AiOrg.fromJson({
      'id': 'org-1',
      'name': 'Acme',
      'plan': 'business.enterprise',
    });

    expect(org.planLabel, 'Business · Enterprise');
  });
}
