import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native/piper_events.dart';
import '../native/piper_node.dart';

enum CallState { idle, calling, ringing, active }

class CallService extends ChangeNotifier {
  static final CallService instance = CallService._();
  CallService._();

  CallState state = CallState.idle;
  String? peerId;
  String? peerName;
  bool isVideoCall = false;
  bool isMuted = false;
  bool isCameraOff = false;
  bool isSpeakerOn = false;
  bool isFrontCamera = true;

  /// Non-null when the last call attempt failed with an error.
  String? callError;

  /// Guard against re-entrant endCall() (e.g. from onIceConnectionState during cleanup).
  bool _ending = false;

  String? selectedMicId;
  String? selectedCameraId;
  String? selectedSpeakerId;

  RTCPeerConnection? _pc;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  MediaStream? _localStream;
  final _pendingIce = <RTCIceCandidate>[];
  RTCSessionDescription? _incomingOffer;

  late PiperNode _piperNode;
  Timer? _callTimer;
  int callDurationSeconds = 0;

  // No external STUN: the app is LAN-only. Host ICE candidates work directly
  // on the local network without NAT traversal.
  static const _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[],
    'iceTransportPolicy': 'all',
  };

  void init(PiperNode node) {
    _piperNode = node;
  }

  Future<void> initRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  // ── Outgoing call ───────────────────────────────────────────────────────────
  Future<void> startCall(String peerId, String peerName, bool isVideo) async {
    this.peerId = peerId;
    this.peerName = peerName;
    isVideoCall = isVideo;
    callError = null;
    state = CallState.calling;
    notifyListeners();

    try {
      if (!await _requestPermissions(isVideo)) {
        callError = 'Microphone${isVideo ? " and camera" : ""} permission denied';
        state = CallState.idle;
        notifyListeners();
        return;
      }
      await _setupPeerConnection();
      _localStream = await _getUserMedia(isVideo);
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }
      if (isVideo) localRenderer.srcObject = _localStream;

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      await _pc!.setLocalDescription(offer);
      _piperNode.sendCallSignal(
          peerId, 'call_offer', jsonEncode({'sdp': offer.sdp, 'is_video': isVideo}));
    } catch (e) {
      callError = e.toString();
      await _cleanup();
      state = CallState.idle;
      notifyListeners();
    }
  }

  // ── Incoming signal handler ─────────────────────────────────────────────────
  Future<void> handleSignal(PiperEvent e) async {
    switch (e.msgType) {
      case 'call_offer':
        if (state != CallState.idle) {
          try {
            _piperNode.sendCallSignal(e.peerId!, 'call_reject', '{}');
          } catch (_) {}
          return;
        }
        final data = jsonDecode(e.content ?? '{}') as Map<String, dynamic>;
        isVideoCall = data['is_video'] == true;
        peerId = e.peerId;
        peerName = e.peerName;
        _incomingOffer = RTCSessionDescription(data['sdp'] as String?, 'offer');
        callError = null;
        state = CallState.ringing;
        notifyListeners();

      case 'call_answer':
        try {
          final data = jsonDecode(e.content ?? '{}') as Map<String, dynamic>;
          await _pc?.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String?, 'answer'));
          for (final c in _pendingIce) {
            await _pc?.addCandidate(c);
          }
          _pendingIce.clear();
          state = CallState.active;
          _startTimer();
          notifyListeners();
        } catch (e) {
          await _cleanup();
          state = CallState.idle;
          notifyListeners();
        }

      case 'call_reject':
        if (!_ending && state != CallState.idle) {
          await _cleanup();
          state = CallState.idle;
          notifyListeners();
        }

      case 'call_end':
        if (!_ending && state != CallState.idle) {
          await _cleanup();
          state = CallState.idle;
          notifyListeners();
        }

      case 'call_ice':
        try {
          final data = jsonDecode(e.content ?? '{}') as Map<String, dynamic>;
          final candidate = RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          );
          final remoteDesc = await _pc?.getRemoteDescription();
          if (remoteDesc != null) {
            await _pc!.addCandidate(candidate);
          } else {
            _pendingIce.add(candidate);
          }
        } catch (_) {}
    }
  }

  // ── Accept incoming call ────────────────────────────────────────────────────
  Future<void> acceptCall() async {
    try {
      if (!await _requestPermissions(isVideoCall)) {
        callError = 'Microphone${isVideoCall ? " and camera" : ""} permission denied';
        try {
          _piperNode.sendCallSignal(peerId!, 'call_reject', '{}');
        } catch (_) {}
        await _cleanup();
        state = CallState.idle;
        notifyListeners();
        return;
      }
      await _setupPeerConnection();
      _localStream = await _getUserMedia(isVideoCall);
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }
      if (isVideoCall) localRenderer.srcObject = _localStream;

      await _pc!.setRemoteDescription(_incomingOffer!);
      for (final c in _pendingIce) {
        await _pc!.addCandidate(c);
      }
      _pendingIce.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _piperNode.sendCallSignal(
          peerId!, 'call_answer', jsonEncode({'sdp': answer.sdp}));
      state = CallState.active;
      _startTimer();
      notifyListeners();
    } catch (e) {
      callError = e.toString();
      try {
        _piperNode.sendCallSignal(peerId!, 'call_reject', '{}');
      } catch (_) {}
      await _cleanup();
      state = CallState.idle;
      notifyListeners();
    }
  }

  Future<void> rejectCall() async {
    try {
      _piperNode.sendCallSignal(peerId!, 'call_reject', '{}');
    } catch (_) {}
    state = CallState.idle;
    peerId = null;
    peerName = null;
    _incomingOffer = null;
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_ending || state == CallState.idle) return;
    _ending = true;
    try {
      if (peerId != null) {
        _piperNode.sendCallSignal(peerId!, 'call_end', '{}');
      }
    } catch (_) {}
    await _cleanup();
    state = CallState.idle;
    _ending = false;
    notifyListeners();
  }

  // ── Media controls ──────────────────────────────────────────────────────────
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    for (final t in _localStream?.getAudioTracks() ?? []) {
      t.enabled = !isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    isCameraOff = !isCameraOff;
    for (final t in _localStream?.getVideoTracks() ?? []) {
      t.enabled = !isCameraOff;
    }
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    isFrontCamera = !isFrontCamera;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    await Helper.setSpeakerphoneOn(isSpeakerOn);
    notifyListeners();
  }

  // ── Device enumeration (desktop) ────────────────────────────────────────────
  Future<List<MediaDeviceInfo>> getAudioInputs() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((d) => d.kind == 'audioinput').toList();
  }

  Future<List<MediaDeviceInfo>> getAudioOutputs() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((d) => d.kind == 'audiooutput').toList();
  }

  Future<List<MediaDeviceInfo>> getVideoInputs() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.where((d) => d.kind == 'videoinput').toList();
  }

  Future<void> saveDevicePreferences(
      {String? micId, String? cameraId, String? speakerId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (micId != null) {
      selectedMicId = micId;
      await prefs.setString('call_mic', micId);
    }
    if (cameraId != null) {
      selectedCameraId = cameraId;
      await prefs.setString('call_camera', cameraId);
    }
    if (speakerId != null) {
      selectedSpeakerId = speakerId;
      await prefs.setString('call_speaker', speakerId);
    }
  }

  Future<void> loadDevicePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    selectedMicId = prefs.getString('call_mic');
    selectedCameraId = prefs.getString('call_camera');
    selectedSpeakerId = prefs.getString('call_speaker');
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  /// Request microphone (and optionally camera) permissions on Android/iOS.
  /// Returns true if all needed permissions are granted.
  Future<bool> _requestPermissions(bool needCamera) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return true;
    final perms = <Permission>[Permission.microphone];
    if (needCamera) perms.add(Permission.camera);
    final statuses = await perms.request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _setupPeerConnection() async {
    await initRenderers();
    _pc = await createPeerConnection(_rtcConfig);
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      try {
        _piperNode.sendCallSignal(
            peerId!,
            'call_ice',
            jsonEncode({
              'candidate': c.candidate,
              'sdpMid': c.sdpMid,
              'sdpMLineIndex': c.sdpMLineIndex,
            }));
      } catch (_) {}
    };
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
      }
    };
    _pc!.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (state != CallState.active) {
          state = CallState.active;
          _startTimer();
          notifyListeners();
        }
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        // Only end on failed — disconnected is transient and fires during cleanup.
        endCall();
      }
    };
  }

  Future<MediaStream> _getUserMedia(bool isVideo) {
    final dynamic audio = selectedMicId != null
        ? {'deviceId': selectedMicId} as dynamic
        : true;
    final dynamic video = isVideo
        ? (selectedCameraId != null
            ? {'deviceId': selectedCameraId} as dynamic
            : _defaultVideoConstraints())
        : false;
    return navigator.mediaDevices.getUserMedia({'audio': audio, 'video': video});
  }

  dynamic _defaultVideoConstraints() {
    final isMobile = !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;
    if (isMobile) {
      return {
        'facingMode': isFrontCamera ? 'user' : 'environment',
      };
    }
    return true;
  }

  void _startTimer() {
    _callTimer?.cancel();
    callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDurationSeconds++;
      notifyListeners();
    });
  }

  Future<void> _cleanup() async {
    _callTimer?.cancel();
    _callTimer = null;
    callDurationSeconds = 0;
    for (final t in _localStream?.getTracks() ?? []) {
      t.stop();
    }
    _localStream?.dispose();
    _localStream = null;
    // Detach event handlers before closing to prevent callbacks during teardown.
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onIceConnectionState = null;
      pc.onTrack = null;
      try {
        await pc.close();
      } catch (_) {}
    }
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _pendingIce.clear();
    _incomingOffer = null;
    peerId = null;
    peerName = null;
    isVideoCall = false;
    isMuted = false;
    isCameraOff = false;
    isSpeakerOn = false;
  }
}
