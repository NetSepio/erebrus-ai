import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Native file locks are process-wide on POSIX, so they alone do NOT protect
/// against two Flutter isolates. A named port serializes isolates first; the
/// file lock also covers separate processes/engines sharing this app's store.
/// No credentials cross the port or enter the lock file.
class SessionMutex {
  SessionMutex({this.lockDirectory});
  final String? lockDirectory;
  @visibleForTesting
  static const portName = 'io.erebrus.ai.auth-session-lock.v2';
  static const _name = portName;

  /// The queue this isolate registered. Statics are per isolate, so a new
  /// engine (an Android activity recreated in a process kept alive by the
  /// foreground service) starts without one.
  static SendPort? _owned;

  /// Call on the main isolate before starting background work. Background
  /// isolates must initialize BackgroundIsolateBinaryMessenger for storage.
  static void initialize() {
    final existing = IsolateNameServer.lookupPortByName(_name);
    if (existing != null) {
      // Background isolates queue on the root isolate's broker.
      if (existing == _owned || RootIsolateToken.instance == null) return;
      // The name server outlives engines. A root isolate that has not claimed
      // the name would otherwise queue forever on a destroyed engine's port.
      IsolateNameServer.removePortNameMapping(_name);
    }
    final queue = Queue<SendPort>();
    var held = false;
    final port = RawReceivePort()..keepIsolateAlive = false;
    void grant() {
      if (!held && queue.isNotEmpty) {
        held = true;
        queue.removeFirst().send(port.sendPort);
      }
    }

    port.handler = (dynamic message) {
      if (message is SendPort) {
        queue.add(message);
      } else if (message == 'release') {
        held = false;
      }
      grant();
    };
    if (IsolateNameServer.registerPortWithName(port.sendPort, _name)) {
      _owned = port.sendPort;
    } else {
      port.close();
    }
  }

  Future<T> synchronized<T>(Future<T> Function() action) async {
    initialize();
    final broker = IsolateNameServer.lookupPortByName(_name)!;
    final reply = ReceivePort();
    broker.send(reply.sendPort);
    final release = await reply.first as SendPort;
    reply.close();
    RandomAccessFile? file;
    var locked = false;
    try {
      final directory = lockDirectory == null
          ? await getApplicationSupportDirectory()
          : Directory(lockDirectory!);
      await directory.create(recursive: true);
      file = await File(
        '${directory.path}/erebrus-ai-session.lock',
      ).open(mode: FileMode.append);
      await file.lock(FileLock.blockingExclusive);
      locked = true;
      return await action();
    } finally {
      try {
        if (locked) await file!.unlock();
        await file?.close();
      } finally {
        release.send('release');
      }
    }
  }
}
