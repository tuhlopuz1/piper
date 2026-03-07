import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'piper_bindings.dart';
import 'piper_events.dart';

/// High-level Dart wrapper around the Go Piper node (via FFI).
///
/// Usage:
/// ```dart
/// final node = PiperNode.create('Alice');
/// node.start();
/// node.events.listen((event) { ... });
/// node.send('Hello!'); // global broadcast
/// node.send('Hey', toPeerID: 'abc-123'); // direct
/// node.stop();
/// ```
class PiperNode {
  final PiperBindings _bindings;
  final int _handle;
  final StreamController<PiperEvent> _eventController =
      StreamController<PiperEvent>.broadcast();

  NativeCallable<EventCallbackC>? _nativeCallback;

  PiperNode._(this._bindings, this._handle);

  /// Create a new node with the given display name.
  /// If [nodeId] is provided, the node reuses that peer ID across sessions.
  factory PiperNode.create(String name, {String? nodeId, String? libraryPath}) {
    final bindings = PiperBindings(libraryPath: libraryPath);
    final namePtr = name.toNativeUtf8();
    final idPtr = (nodeId ?? '').toNativeUtf8();
    final handle = bindings.createNode(namePtr, idPtr);
    malloc.free(namePtr);
    malloc.free(idPtr);
    return PiperNode._(bindings, handle);
  }

  /// Start the node (TCP listener + peer discovery).
  /// Throws on failure.
  void start() {
    final errPtr = _bindings.startNode(_handle);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception('Failed to start node: $err');
    }
    _setupEventCallback();
  }

  /// Update the display name used in outgoing messages and discovery.
  void setName(String name) {
    final ptr = name.toNativeUtf8();
    _bindings.setNodeName(_handle, ptr);
    malloc.free(ptr);
  }

  /// Configure where received files are saved. Call before start().
  void setDownloadsDir(String path) {
    final ptr = path.toNativeUtf8();
    _bindings.setDownloadsDir(_handle, ptr);
    malloc.free(ptr);
  }

  /// Stop the node and release resources.
  void stop() {
    _nativeCallback?.close();
    _nativeCallback = null;
    _bindings.stopNode(_handle);
    _eventController.close();
  }

  /// The node's stable peer ID.
  String get id {
    final ptr = _bindings.nodeID(_handle);
    final val = ptr.toDartString();
    _bindings.freeString(ptr);
    return val;
  }

  /// The node's display name.
  String get name {
    final ptr = _bindings.nodeName(_handle);
    final val = ptr.toDartString();
    _bindings.freeString(ptr);
    return val;
  }

  /// Stream of events from the Go backend.
  Stream<PiperEvent> get events => _eventController.stream;

  // ─── Messaging ─────────────────────────────────────────────────────────────

  /// Send a text message. If [toPeerID] is null, broadcasts globally.
  void send(String text, {String? toPeerID}) {
    final textPtr = text.toNativeUtf8();
    final toPtr = (toPeerID ?? '').toNativeUtf8();
    _bindings.send(_handle, textPtr, toPtr);
    malloc.free(textPtr);
    malloc.free(toPtr);
  }

  /// Send an encrypted message to a group.
  void sendGroup(String text, String groupID) {
    final textPtr = text.toNativeUtf8();
    final gidPtr = groupID.toNativeUtf8();
    _bindings.sendGroup(_handle, textPtr, gidPtr);
    malloc.free(textPtr);
    malloc.free(gidPtr);
  }

  /// Send a file to a single peer. Throws on error.
  void sendFile(String peerID, String filePath) {
    final pidPtr = peerID.toNativeUtf8();
    final pathPtr = filePath.toNativeUtf8();
    final errPtr = _bindings.sendFile(_handle, pidPtr, pathPtr);
    malloc.free(pidPtr);
    malloc.free(pathPtr);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception('SendFile failed: $err');
    }
  }

  /// Send a file to all members of a group. Throws on error.
  void sendFileToGroup(String groupID, String filePath) {
    final gidPtr = groupID.toNativeUtf8();
    final pathPtr = filePath.toNativeUtf8();
    final errPtr = _bindings.sendFileToGroup(_handle, gidPtr, pathPtr);
    malloc.free(gidPtr);
    malloc.free(pathPtr);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception('SendFileToGroup failed: $err');
    }
  }

  /// Send a voice attachment to a single peer. Throws on error.
  void sendVoice(String peerID, String filePath, {required int durationSec}) {
    final pidPtr = peerID.toNativeUtf8();
    final pathPtr = filePath.toNativeUtf8();
    final errPtr = _bindings.sendVoice(_handle, pidPtr, pathPtr, durationSec);
    malloc.free(pidPtr);
    malloc.free(pathPtr);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception('SendVoice failed: $err');
    }
  }

  /// Send a voice attachment to all members of a group. Throws on error.
  void sendVoiceToGroup(String groupID, String filePath,
      {required int durationSec}) {
    final gidPtr = groupID.toNativeUtf8();
    final pathPtr = filePath.toNativeUtf8();
    final errPtr =
        _bindings.sendVoiceToGroup(_handle, gidPtr, pathPtr, durationSec);
    malloc.free(gidPtr);
    malloc.free(pathPtr);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception('SendVoiceToGroup failed: $err');
    }
  }

  // ─── Call signaling ────────────────────────────────────────────────────────

  /// Send a call signal (offer/answer/ice/reject/end) to a peer. Throws on error.
  void sendCallSignal(String toPeerId, String signalType, String payload) {
    final peerPtr = toPeerId.toNativeUtf8();
    final typePtr = signalType.toNativeUtf8();
    final payloadPtr = payload.toNativeUtf8();
    final errPtr =
        _bindings.sendCallSignal(_handle, peerPtr, typePtr, payloadPtr);
    malloc.free(peerPtr);
    malloc.free(typePtr);
    malloc.free(payloadPtr);
    if (errPtr != nullptr) {
      final err = errPtr.toDartString();
      _bindings.freeString(errPtr);
      throw Exception(err);
    }
  }

  // ─── Groups ────────────────────────────────────────────────────────────────

  /// Create a new group and return its ID.
  String createGroup(String name) {
    final namePtr = name.toNativeUtf8();
    final idPtr = _bindings.createGroup(_handle, namePtr);
    malloc.free(namePtr);
    final gid = idPtr.toDartString();
    _bindings.freeString(idPtr);
    return gid;
  }

  /// Invite a peer to a group.
  void inviteToGroup(String groupID, String peerID) {
    final gidPtr = groupID.toNativeUtf8();
    final pidPtr = peerID.toNativeUtf8();
    _bindings.inviteToGroup(_handle, gidPtr, pidPtr);
    malloc.free(gidPtr);
    malloc.free(pidPtr);
  }

  /// Leave a group.
  void leaveGroup(String groupID) {
    final gidPtr = groupID.toNativeUtf8();
    _bindings.leaveGroup(_handle, gidPtr);
    malloc.free(gidPtr);
  }

  // ─── Network helpers ───────────────────────────────────────────────────────

  /// Returns all non-loopback IPv4 addresses on this device, including
  /// AP/hotspot interfaces hidden from libwebrtc's network enumeration.
  List<String> localIPs() {
    final ptr = _bindings.localIPs(_handle);
    final jsonStr = ptr.toDartString();
    _bindings.freeString(ptr);
    final decoded = jsonDecode(jsonStr);
    if (decoded == null) return const [];
    return (decoded as List<dynamic>).map((e) => e as String).toList();
  }

  /// Returns the UDP port of the local TURN relay server, or 0 if unavailable.
  /// Use with turn:<peerIP>:<port> in WebRTC ICE server config so calls work
  /// on WiFi Direct networks where libwebrtc cannot enumerate the AP interface.
  int getTURNPort() {
    return _bindings.getTURNPort(_handle);
  }

  /// Returns the TCP remote IP for [peerID] as seen at the Go transport layer,
  /// or empty string if unknown.
  String getPeerIP(String peerID) {
    final pidPtr = peerID.toNativeUtf8();
    final ptr = _bindings.getPeerIP(_handle, pidPtr);
    malloc.free(pidPtr);
    final val = ptr.toDartString();
    _bindings.freeString(ptr);
    return val;
  }

  // ─── Queries ───────────────────────────────────────────────────────────────

  /// Get a snapshot of all known peers.
  List<PeerInfo> get peers {
    final ptr = _bindings.listPeers(_handle);
    final jsonStr = ptr.toDartString();
    _bindings.freeString(ptr);
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => PeerInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get a snapshot of all groups.
  List<GroupInfo> get groups {
    final ptr = _bindings.listGroups(_handle);
    final jsonStr = ptr.toDartString();
    _bindings.freeString(ptr);
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => GroupInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Mesh topology ─────────────────────────────────────────────────────────

  /// Returns the current mesh topology as JSON with nodes and edges.
  Map<String, dynamic> getTopology() {
    final ptr = _bindings.getTopology(_handle);
    final jsonStr = ptr.toDartString();
    _bindings.freeString(ptr);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// Returns the routing table as {targetPeerID: nextHopPeerID}.
  Map<String, String> getRouteTable() {
    final ptr = _bindings.getRouteTable(_handle);
    final jsonStr = ptr.toDartString();
    _bindings.freeString(ptr);
    final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  void _setupEventCallback() {
    // NativeCallable.listener wraps a Dart closure so it can be called from
    // any native thread. The Go event-pump goroutine invokes this callback
    // with JSON; Dart schedules the closure on this isolate automatically.
    _nativeCallback = NativeCallable<EventCallbackC>.listener(
      _handleNativeEvent,
    );
    _bindings.setEventCallback(_handle, _nativeCallback!.nativeFunction);
  }

  void _handleNativeEvent(Pointer<Utf8> eventJSON) {
    // Copy the string FIRST, then free the C memory.
    // The Go event pump does NOT free this — Dart owns the lifetime
    // because NativeCallable.listener is asynchronous.
    final jsonStr = eventJSON.toDartString();
    _bindings.freeString(eventJSON);
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final event = PiperEvent.fromJson(map);
      if (!_eventController.isClosed) {
        _eventController.add(event);
      }
    } catch (e) {
      // Malformed event — ignore silently.
    }
  }
}
