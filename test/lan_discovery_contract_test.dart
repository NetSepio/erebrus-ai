import 'package:erebrus_ai/services/local_server_service.dart';
import 'package:erebrus_ai/services/mdns_config.dart';
import 'package:erebrus_ai/services/node_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LAN discovery contract', () {
    test('installation node ID is stable', () async {
      SharedPreferences.setMockInitialValues({});
      resetMdnsNodeIdentityForTest();
      final first = await loadMdnsNodeIdentity();
      resetMdnsNodeIdentityForTest();
      final second = await loadMdnsNodeIdentity();

      expect(first.id, isNotEmpty);
      expect(second.id, first.id);
      expect(first.displayName, isNotEmpty);
    });

    test('prefers a routable IPv4 address for peer HTTP requests', () {
      expect(
        preferredMdnsHost(const [
          '::1',
          '169.254.20.4',
          'fe80::1',
          '192.168.1.24',
        ]),
        '192.168.1.24',
      );
    });

    test('rejects own modern and legacy broadcasts', () {
      expect(
        isOwnMdnsService(
          advertisedNodeId: 'same-installation',
          localNodeId: 'same-installation',
          host: '192.168.1.24',
          advertisedPort: 11434,
          localPort: 11434,
          localServerRunning: true,
          localAddresses: const {'192.168.1.24'},
        ),
        isTrue,
      );
      expect(
        isOwnMdnsService(
          advertisedNodeId: '',
          localNodeId: 'same-installation',
          host: '192.168.1.24',
          advertisedPort: 11434,
          localPort: 11434,
          localServerRunning: true,
          localAddresses: const {'192.168.1.24'},
        ),
        isTrue,
      );
      expect(
        isOwnMdnsService(
          advertisedNodeId: 'another-installation',
          localNodeId: 'same-installation',
          host: '192.168.1.50',
          advertisedPort: 11434,
          localPort: 11434,
          localServerRunning: true,
          localAddresses: const {'192.168.1.24'},
        ),
        isFalse,
      );
    });

    test('model metadata is public but inference is authenticated', () {
      expect(isPublicLocalServerMetadataRequest('GET', 'health'), isTrue);
      expect(isPublicLocalServerMetadataRequest('GET', 'v1/models'), isTrue);
      expect(
        isPublicLocalServerMetadataRequest('POST', 'v1/chat/completions'),
        isFalse,
      );
    });

    test('formats IPv6 model-list URLs correctly', () {
      const node = DiscoveredNode(
        id: 'peer',
        name: 'Peer Mac',
        host: 'fe80::1234',
        port: 11434,
      );
      expect(node.modelListUri.path, '/v1/models');
      expect(node.modelListUri.host, 'fe80::1234');
      expect(node.modelListUri.toString(), contains('[fe80::1234]'));
    });
  });
}
