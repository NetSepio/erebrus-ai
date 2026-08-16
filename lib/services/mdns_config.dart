import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// DNS-SD service identity shared by advertising, discovery and platform
/// permission metadata. The family name is deliberately `erebrusai` without a
/// hyphen.
const kErebrusAiMdnsType = '_erebrusai._tcp';
const kMdnsNodeIdAttribute = 'node_id';
const kMdnsProtocolAttribute = 'protocol';
const kMdnsProtocolVersion = '1';

const _nodeIdPreference = 'erebrus_lan_node_id';
Future<MdnsNodeIdentity>? _identityFuture;

class MdnsNodeIdentity {
  const MdnsNodeIdentity({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// Returns a stable identity for this app installation. The identifier is
/// advertised only on the local network and lets the app reject its own mDNS
/// broadcast without relying on unstable IP addresses or service names.
Future<MdnsNodeIdentity> loadMdnsNodeIdentity() =>
    _identityFuture ??= _loadMdnsNodeIdentity();

Future<MdnsNodeIdentity> _loadMdnsNodeIdentity() async {
  final preferences = await SharedPreferences.getInstance();
  var id = preferences.getString(_nodeIdPreference)?.trim() ?? '';
  if (id.isEmpty) {
    id = const Uuid().v4();
    await preferences.setString(_nodeIdPreference, id);
  }

  var hostname = '';
  try {
    hostname = Platform.localHostname.trim();
  } on Object {
    // Some mobile platforms do not expose a hostname.
  }
  final generic =
      hostname.isEmpty ||
      hostname.toLowerCase() == 'localhost' ||
      hostname.toLowerCase() == 'localhost.local';
  final displayName = generic ? 'Erebrus AI node' : '$hostname · Erebrus AI';
  return MdnsNodeIdentity(id: id, displayName: displayName);
}

@visibleForTesting
void resetMdnsNodeIdentityForTest() => _identityFuture = null;

String? preferredMdnsHost(Iterable<String> addresses) {
  final usable = addresses
      .map((address) => address.trim())
      .where((address) => address.isNotEmpty)
      .where((address) => address != '0.0.0.0' && address != '::')
      .toList(growable: false);
  for (final address in usable) {
    if (!address.contains(':') &&
        !address.startsWith('127.') &&
        !address.startsWith('169.254.')) {
      return address;
    }
  }
  for (final address in usable) {
    if (!address.startsWith('127.') && address != '::1') return address;
  }
  return usable.firstOrNull;
}

/// Identifies this installation's own service, including broadcasts from app
/// versions that predate the stable node ID TXT attribute.
bool isOwnMdnsService({
  required String advertisedNodeId,
  required String localNodeId,
  required String host,
  required int advertisedPort,
  required int localPort,
  required bool localServerRunning,
  required Set<String> localAddresses,
}) {
  if (advertisedNodeId.isNotEmpty && advertisedNodeId == localNodeId) {
    return true;
  }
  return advertisedNodeId.isEmpty &&
      localServerRunning &&
      advertisedPort == localPort &&
      localAddresses.contains(host);
}
