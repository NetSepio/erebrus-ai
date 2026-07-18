import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// Discovers Erebrus AI nodes advertising `_erebrusai._tcp` on the LAN.
class NodeDiscoveryService extends ChangeNotifier {
  NodeDiscoveryService._();
  static final NodeDiscoveryService _instance = NodeDiscoveryService._();
  static NodeDiscoveryService get instance => _instance;

  final List<DiscoveredNode> _nodes = [];
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  bool _running = false;

  List<DiscoveredNode> get nodes => List.unmodifiable(_nodes);
  bool get isRunning => _running;

  bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

  /// Starts continuous mDNS discovery.
  Future<void> start() async {
    if (_running || kIsWeb || _inTest) return;
    _running = true;
    notifyListeners();

    try {
      _discovery = BonsoirDiscovery(type: '_erebrusai._tcp');
      await _discovery!.initialize();
      _subscription = _discovery!.eventStream?.listen(_onEvent);
      await _discovery!.start();
    } catch (e) {
      debugPrint('[Discovery] start failed: $e');
      _running = false;
      notifyListeners();
    }
  }

  /// Stops discovery and clears the node list.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
    _nodes.clear();
    _running = false;
    notifyListeners();
  }

  void _onEvent(BonsoirDiscoveryEvent event) async {
    if (event is BonsoirDiscoveryServiceFoundEvent) {
      try {
        _discovery?.serviceResolver.resolveService(event.service);
      } catch (e) {
        debugPrint('[Discovery] resolve failed: $e');
      }
    } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
      _addOrUpdate(event.service);
    } else if (event is BonsoirDiscoveryServiceLostEvent) {
      _remove(event.service);
    }
  }

  void _addOrUpdate(BonsoirService service) {
    final host = service.hostAddress ?? '127.0.0.1';
    final node = DiscoveredNode(
      name: service.name,
      host: host,
      port: service.port,
    );
    _nodes.removeWhere((n) => n.name == node.name && n.host == node.host);
    _nodes.add(node);
    notifyListeners();
  }

  void _remove(BonsoirService service) {
    _nodes.removeWhere((n) => n.name == service.name);
    notifyListeners();
  }
}

/// A node discovered on the local network.
class DiscoveredNode {
  const DiscoveredNode({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;

  String get url => 'http://$host:$port';

  @override
  String toString() => '$name @ $host:$port';
}
