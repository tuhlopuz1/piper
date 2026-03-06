import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native/piper_events.dart';
import '../native/piper_node.dart';

enum CallState { idle, calling, ringing, active }

enum CallDirection { incoming, outgoing }

class CallSession {
  final String callId;
  final String peerId;
  final CallDirection direction;
  final DateTime createdAt;
  DateTime lastSignalAt;

  CallSession({
    required this.callId,
    required this.peerId,
    required this.direction,
    required this.createdAt,
    required this.lastSignalAt,
  });
}

class _PendingAck {
  final String callId;
  final int seq;
  final String signalType;
  final Map<String, dynamic> payload;
  int retries = 0;
  Timer? timer;

  _PendingAck({
    required this.callId,
    required this.seq,
    required this.signalType,
    required this.payload,
  });

  String get key => '$callId:$signalType:$seq';
}

class CallService extends ChangeNotifier {
  static final CallService instance = CallService._();
  CallService._();

  static const Duration _offerTimeout = Duration(seconds: 40);
  static const Duration _ringTimeout = Duration(seconds: 60);
  static const Duration _iceQuietTimeout = Duration(seconds: 45);
  static const Duration _hardCleanupTimeout = Duration(seconds: 5);
  static const List<Duration> _ackBackoff = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1500),
  ];

  CallState state = CallState.idle;
  String? peerId;
  String? peerName;
  bool isVideoCall = false;
  bool isMuted = false;
  bool isCameraOff = false;
  bool isSpeakerOn = false;
  bool isFrontCamera = true;

  String? callError;

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

  CallSession? _session;
  int _localSeq = 0;
  final Set<String> _seenSignals = <String>{};
  final ListQueue<String> _seenSignalOrder = ListQueue<String>();
  final Map<String, _PendingAck> _pendingAcks = <String, _PendingAck>{};
  final Map<String, List<Map<String, dynamic>>> _earlyIceByCall =
      <String, List<Map<String, dynamic>>>{};
  final ListQueue<Map<String, dynamic>> _outgoingIceQueue =
      ListQueue<Map<String, dynamic>>();

  Timer? _offerTimer;
  Timer? _ringTimer;
  Timer? _iceQuietTimer;
  Timer? _hardCleanupTimer;
  Timer? _iceFlushTimer;
  bool _iceFlushInProgress = false;

  final Random _rng = Random();
  bool _ending = false;

  final Map<String, int> _counters = <String, int>{
    'call_offer_sent': 0,
    'call_offer_received': 0,
    'call_established': 0,
    'call_drop_before_answer': 0,
    'call_signal_retry': 0,
    'call_ui_duplicate_blocked': 0,
    'call_stuck_state_recovered': 0,
  };

  final ListQueue<String> _eventLog = ListQueue<String>();

  static const _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[],
    'iceTransportPolicy': 'all',
  };

  String? get currentCallId => _session?.callId;
  Map<String, int> get counters => Map.unmodifiable(_counters);
  List<String> get recentCallLog => List.unmodifiable(_eventLog);

  void init(PiperNode node) {
    _piperNode = node;
  }

  void recordUiDuplicateBlocked() {
    _inc('call_ui_duplicate_blocked');
  }

  Future<void> initRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> startCall(String peerId, String peerName, bool isVideo) async {
    if (state != CallState.idle || _session != null) {
      _log('startCall blocked: state=$state peer=$peerId');
      return;
    }

    this.peerId = peerId;
    this.peerName = peerName;
    isVideoCall = isVideo;
    callError = null;

    final session = CallSession(
      callId: _newCallId(),
      peerId: peerId,
      direction: CallDirection.outgoing,
      createdAt: DateTime.now(),
      lastSignalAt: DateTime.now(),
    );
    _session = session;
    _localSeq = 0;

    state = CallState.calling;
    _startOfferWatchdog(session.callId);
    _touchSignal();
    notifyListeners();

    try {
      if (!await _requestPermissions(isVideo)) {
        callError =
            'Microphone${isVideo ? " and camera" : ""} permission denied';
        await _failAndReset('permissions denied');
        return;
      }

      await loadDevicePreferences();
      await _setupPeerConnection();
      _localStream = await _getUserMedia(isVideo);
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }
      localRenderer.srcObject = _localStream;

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      await _pc!.setLocalDescription(offer);

      _inc('call_offer_sent');
      await _sendSignal(
        'call_offer',
        {
          'sdp': offer.sdp,
          'is_video': isVideo,
        },
      );
      _log('offer sent call_id=${session.callId}');
    } catch (e) {
      callError = e.toString();
      await _failAndReset('startCall error: $e');
    }
  }

  Future<void> handleSignal(PiperEvent e) async {
    final msgType = e.msgType;
    if (msgType == null || e.peerId == null) return;

    Map<String, dynamic> data;
    try {
      data = _decodePayload(e.content);
    } catch (_) {
      _log('drop malformed payload type=$msgType');
      return;
    }

    final incomingCallId = (data['call_id'] as String?) ?? '';
    final seq = (data['seq'] as num?)?.toInt() ?? 0;

    if (incomingCallId.isEmpty && msgType != 'call_offer') {
      _log('drop $msgType without call_id');
      return;
    }

    switch (msgType) {
      case 'call_offer':
        if (incomingCallId.isNotEmpty &&
            seq > 0 &&
            !_markSeen(msgType, incomingCallId, seq, e.peerId!)) {
          _log('dedup drop type=$msgType call_id=$incomingCallId seq=$seq');
          return;
        }
        await _handleOffer(e, data);
        return;

      case 'call_answer':
        if (incomingCallId.isNotEmpty &&
            seq > 0 &&
            !_markSeen(msgType, incomingCallId, seq, e.peerId!)) {
          _log('dedup drop type=$msgType call_id=$incomingCallId seq=$seq');
          return;
        }
        await _handleAnswer(data);
        return;

      case 'call_ice':
        if (_session == null || _session!.callId != incomingCallId) {
          _stashEarlyIce(incomingCallId, data);
          return;
        }
        await _handleIce(data);
        return;

      case 'call_reject':
      case 'call_end':
      case 'call_busy':
        if (incomingCallId.isNotEmpty &&
            seq > 0 &&
            !_markSeen(msgType, incomingCallId, seq, e.peerId!)) {
          _log('dedup drop type=$msgType call_id=$incomingCallId seq=$seq');
          return;
        }
        await _handleRemoteTerminate(msgType, data);
        return;

      case 'call_ack':
        _handleAck(data);
        return;

      default:
        return;
    }
  }

  Future<void> acceptCall() async {
    final s = _session;
    if (state != CallState.ringing ||
        s == null ||
        s.direction != CallDirection.incoming) {
      _log('accept blocked state=$state');
      return;
    }

    try {
      if (!await _requestPermissions(isVideoCall)) {
        callError =
            'Microphone${isVideoCall ? " and camera" : ""} permission denied';
        await _sendSignal('call_reject', {'reason': 'permission_denied'},
            expectAck: true);
        await _failAndReset('accept permissions denied');
        return;
      }

      await loadDevicePreferences();
      await _setupPeerConnection();
      _localStream = await _getUserMedia(isVideoCall);
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }
      localRenderer.srcObject = _localStream;

      if (_incomingOffer == null) {
        await _failAndReset('missing incoming offer');
        return;
      }

      await _pc!.setRemoteDescription(_incomingOffer!);
      for (final c in _pendingIce) {
        await _pc!.addCandidate(c);
      }
      _pendingIce.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _sendSignal(
        'call_answer',
        {'sdp': answer.sdp},
      );

      state = CallState.calling;
      _cancelOfferAndRingTimers();
      _touchSignal();
      notifyListeners();
    } catch (e) {
      callError = e.toString();
      await _sendSignal('call_reject', {'reason': 'accept_failed'},
          expectAck: true);
      await _failAndReset('accept error: $e');
    }
  }

  Future<void> rejectCall() async {
    final s = _session;
    if (s == null) {
      await _resetToIdle();
      return;
    }

    try {
      await _sendSignal('call_reject', {'reason': 'rejected'}, expectAck: true);
    } catch (_) {}
    await _resetToIdle();
  }

  Future<void> endCall() async {
    if (_ending || state == CallState.idle) return;
    _ending = true;
    final isEarlyDrop =
        state == CallState.calling || state == CallState.ringing;

    try {
      await _sendSignal('call_end', {'reason': 'local_end'}, expectAck: true);
    } catch (_) {}

    if (isEarlyDrop) {
      _inc('call_drop_before_answer');
    }
    await _resetToIdle();
    _ending = false;
  }

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

  Future<void> setAudioOutput(String deviceId) async {
    selectedSpeakerId = deviceId;
    try {
      await remoteRenderer.audioOutput(deviceId);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setMicrophone(String deviceId) async {
    selectedMicId = deviceId;
    if (_pc == null || _localStream == null) return;
    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': {'deviceId': deviceId},
      'video': false
    });
    final newTrack = newStream.getAudioTracks().first;
    final senders = await _pc!.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'audio') {
        await sender.replaceTrack(newTrack);
      }
    }
    for (final t in _localStream!.getAudioTracks()) {
      t.stop();
      _localStream!.removeTrack(t);
    }
    _localStream!.addTrack(newTrack);
    notifyListeners();
  }

  Future<void> setCamera(String deviceId) async {
    selectedCameraId = deviceId;
    if (_pc == null || _localStream == null) return;
    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {'deviceId': deviceId}
    });
    final newTrack = newStream.getVideoTracks().first;
    final senders = await _pc!.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        await sender.replaceTrack(newTrack);
      }
    }
    for (final t in _localStream!.getVideoTracks()) {
      t.stop();
      _localStream!.removeTrack(t);
    }
    _localStream!.addTrack(newTrack);
    localRenderer.srcObject = _localStream;
    notifyListeners();
  }

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
      if (c.candidate == null || _session == null) return;
      _outgoingIceQueue.add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
      _flushOutgoingIceQueue();
    };

    _pc!.onTrack = (e) async {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
      } else {
        remoteRenderer.srcObject ??= await createLocalMediaStream('remote');
        remoteRenderer.srcObject!.addTrack(e.track);
      }
      _touchSignal();
      notifyListeners();
    };

    _pc!.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (state != CallState.active) {
          state = CallState.active;
          _startTimer();
          _cancelOfferAndRingTimers();
          _touchSignal();
          _inc('call_established');
          notifyListeners();
        }
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _inc('call_stuck_state_recovered');
        unawaited(endCall());
      }
    };
  }

  Future<void> _handleOffer(PiperEvent e, Map<String, dynamic> data) async {
    final incomingPeerId = e.peerId!;
    final incomingPeerName = e.peerName ?? 'Unknown';
    final callId = (data['call_id'] as String?) ?? _newCallId();

    if (state != CallState.idle || _session != null) {
      await _sendRawSignal(
        incomingPeerId,
        'call_busy',
        {
          'call_id': callId,
          'reason': 'busy',
        },
        expectAck: true,
      );
      return;
    }

    _session = CallSession(
      callId: callId,
      peerId: incomingPeerId,
      direction: CallDirection.incoming,
      createdAt: DateTime.now(),
      lastSignalAt: DateTime.now(),
    );
    _localSeq = 0;

    isVideoCall = data['is_video'] == true;
    peerId = incomingPeerId;
    peerName = incomingPeerName;
    _incomingOffer = RTCSessionDescription(data['sdp'] as String?, 'offer');
    callError = null;
    state = CallState.ringing;
    _inc('call_offer_received');

    _startRingWatchdog(callId);
    _touchSignal();
    _drainEarlyIce(callId);
    notifyListeners();
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final s = _session;
    final callId = data['call_id'] as String?;
    if (s == null ||
        callId != s.callId ||
        s.direction != CallDirection.outgoing) {
      return;
    }

    try {
      await _pc?.setRemoteDescription(
        RTCSessionDescription(data['sdp'] as String?, 'answer'),
      );
      for (final c in _pendingIce) {
        await _pc?.addCandidate(c);
      }
      _pendingIce.clear();
      _touchSignal();
      _cancelOfferAndRingTimers();

      if (state != CallState.active) {
        state = CallState.calling;
      }
      notifyListeners();
    } catch (e) {
      await _failAndReset('answer handling failed: $e');
    }
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final s = _session;
    final callId = data['call_id'] as String?;
    if (s == null || callId != s.callId) return;

    try {
      final candidate = RTCIceCandidate(
        data['candidate'] as String?,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      );
      final remoteDesc = await _pc?.getRemoteDescription();
      if (remoteDesc != null && _pc != null) {
        await _pc!.addCandidate(candidate);
      } else {
        _pendingIce.add(candidate);
      }
      _touchSignal();
    } catch (_) {}
  }

  Future<void> _handleRemoteTerminate(
      String type, Map<String, dynamic> data) async {
    final s = _session;
    final callId = data['call_id'] as String?;
    if (s == null || callId != s.callId) {
      return;
    }

    final seq = (data['seq'] as num?)?.toInt();
    if (seq != null && seq > 0) {
      await _sendSignal('call_ack', {
        'ack_seq': seq,
        'ack_type': type,
      });
    }

    if ((state == CallState.calling || state == CallState.ringing) &&
        (type == 'call_reject' || type == 'call_busy' || type == 'call_end')) {
      _inc('call_drop_before_answer');
    }

    await _resetToIdle();
  }

  void _handleAck(Map<String, dynamic> data) {
    final callId = data['call_id'] as String?;
    final ackType = data['ack_type'] as String?;
    final ackSeq = (data['ack_seq'] as num?)?.toInt();
    if (callId == null || ackType == null || ackSeq == null) return;

    final key = '$callId:$ackType:$ackSeq';
    final pending = _pendingAcks.remove(key);
    pending?.timer?.cancel();
  }

  Future<void> _sendSignal(
    String signalType,
    Map<String, dynamic> payload, {
    bool expectAck = false,
  }) async {
    final s = _session;
    if (s == null) return;
    await _sendRawSignal(s.peerId, signalType, payload,
        expectAck: expectAck, callId: s.callId);
  }

  Future<void> _sendRawSignal(
    String toPeerId,
    String signalType,
    Map<String, dynamic> payload, {
    bool expectAck = false,
    String? callId,
  }) async {
    final effectiveCallId = callId ?? _session?.callId;
    if (effectiveCallId != null && effectiveCallId.isNotEmpty) {
      payload['call_id'] = effectiveCallId;
    }
    if (signalType != 'call_ack') {
      _localSeq++;
      payload['seq'] = _localSeq;
    }

    final body = jsonEncode(payload);

    // Critical signals (offer/answer) get retries; others are fire-and-forget.
    final isCritical = signalType == 'call_offer' ||
        signalType == 'call_answer' ||
        signalType == 'call_end' ||
        signalType == 'call_reject';
    final maxAttempts = isCritical ? 3 : 1;
    Object? lastError;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
        if (_session == null) return; // call ended while waiting
      }
      try {
        _piperNode.sendCallSignal(toPeerId, signalType, body);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        _log('sendRawSignal attempt=$attempt type=$signalType err=$e');
      }
    }
    if (lastError != null) throw lastError!;

    _touchSignal();

    if (expectAck && signalType != 'call_ack' && effectiveCallId != null) {
      final pending = _PendingAck(
        callId: effectiveCallId,
        seq: payload['seq'] as int,
        signalType: signalType,
        payload: Map<String, dynamic>.from(payload),
      );
      _pendingAcks[pending.key] = pending;
      _scheduleAckRetry(pending, toPeerId);
    }
  }

  void _scheduleAckRetry(_PendingAck pending, String toPeerId) {
    if (pending.retries >= _ackBackoff.length) {
      _pendingAcks.remove(pending.key);
      pending.timer?.cancel();
      return;
    }

    final delay = _ackBackoff[pending.retries];
    pending.timer?.cancel();
    pending.timer = Timer(delay, () async {
      if (!_pendingAcks.containsKey(pending.key)) return;
      pending.retries++;
      _inc('call_signal_retry');
      try {
        _piperNode.sendCallSignal(
            toPeerId, pending.signalType, jsonEncode(pending.payload));
      } catch (_) {}
      _scheduleAckRetry(pending, toPeerId);
    });
  }

  void _startOfferWatchdog(String callId) {
    _offerTimer?.cancel();
    _offerTimer = Timer(_offerTimeout, () async {
      if (_session?.callId == callId && state == CallState.calling) {
        _inc('call_drop_before_answer');
        await _sendSignal('call_end', {'reason': 'offer_timeout'},
            expectAck: true);
        await _failAndReset('offer timeout');
      }
    });
  }

  void _startRingWatchdog(String callId) {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () async {
      if (_session?.callId == callId && state == CallState.ringing) {
        _inc('call_drop_before_answer');
        await _sendSignal('call_reject', {'reason': 'ring_timeout'},
            expectAck: true);
        await _failAndReset('ring timeout');
      }
    });
  }

  void _touchSignal() {
    final now = DateTime.now();
    if (_session != null) {
      _session!.lastSignalAt = now;
    }

    _iceQuietTimer?.cancel();
    if (state == CallState.calling || state == CallState.ringing) {
      _iceQuietTimer = Timer(_iceQuietTimeout, () async {
        if (state == CallState.idle || _session == null) return;
        _inc('call_stuck_state_recovered');
        await _sendSignal('call_end', {'reason': 'ice_quiet_timeout'},
            expectAck: true);
        await _failAndReset('ice quiet watchdog');
      });
    }
  }

  void _cancelOfferAndRingTimers() {
    _offerTimer?.cancel();
    _offerTimer = null;
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  Future<void> _failAndReset(String reason) async {
    _log(reason);
    await _resetToIdle();
  }

  Future<void> _resetToIdle() async {
    _clearSessionForIdle();
    state = CallState.idle;
    notifyListeners();

    _hardCleanupTimer?.cancel();
    _hardCleanupTimer = Timer(_hardCleanupTimeout, () {
      _inc('call_stuck_state_recovered');
      _log('hard cleanup timer fired');
    });

    await _cleanup();

    _hardCleanupTimer?.cancel();
    _hardCleanupTimer = null;
  }

  Future<void> _cleanup() async {
    _callTimer?.cancel();
    _callTimer = null;
    callDurationSeconds = 0;

    _offerTimer?.cancel();
    _offerTimer = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    _iceQuietTimer?.cancel();
    _iceQuietTimer = null;
    _iceFlushTimer?.cancel();
    _iceFlushTimer = null;
    _iceFlushInProgress = false;
    _outgoingIceQueue.clear();
    _earlyIceByCall.clear();

    for (final t in _localStream?.getTracks() ?? []) {
      t.stop();
    }
    _localStream?.dispose();
    _localStream = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onIceConnectionState = null;
      pc.onTrack = null;
      try {
        await pc.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _pendingIce.clear();
  }

  void _clearSessionForIdle() {
    for (final a in _pendingAcks.values) {
      a.timer?.cancel();
    }
    _pendingAcks.clear();

    _pendingIce.clear();
    _incomingOffer = null;
    _session = null;
    _localSeq = 0;

    peerId = null;
    peerName = null;
    isVideoCall = false;
    isMuted = false;
    isCameraOff = false;
    isSpeakerOn = false;

    selectedMicId = null;
    selectedCameraId = null;
    selectedSpeakerId = null;
  }

  Future<MediaStream> _getUserMedia(bool isVideo) {
    final dynamic audio =
        selectedMicId != null ? {'deviceId': selectedMicId} as dynamic : true;
    final dynamic video = isVideo
        ? (selectedCameraId != null
            ? {'deviceId': selectedCameraId} as dynamic
            : _defaultVideoConstraints())
        : false;
    return navigator.mediaDevices
        .getUserMedia({'audio': audio, 'video': video});
  }

  dynamic _defaultVideoConstraints() {
    final isMobile =
        !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;
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

  bool _markSeen(String type, String callId, int seq, String fromPeer) {
    final key = '$fromPeer:$callId:$type:$seq';
    if (_seenSignals.contains(key)) return false;
    _seenSignals.add(key);
    _seenSignalOrder.addLast(key);
    while (_seenSignalOrder.length > 512) {
      final old = _seenSignalOrder.removeFirst();
      _seenSignals.remove(old);
    }
    return true;
  }

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  String _newCallId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = _rng.nextInt(0x7fffffff);
    return '$now-$rand';
  }

  void _inc(String key) {
    _counters[key] = (_counters[key] ?? 0) + 1;
  }

  void _stashEarlyIce(String callId, Map<String, dynamic> data) {
    if (callId.isEmpty) return;
    _earlyIceByCall.putIfAbsent(callId, () => <Map<String, dynamic>>[]);
    _earlyIceByCall[callId]!.add(Map<String, dynamic>.from(data));
    if (_earlyIceByCall[callId]!.length > 128) {
      _earlyIceByCall[callId]!.removeAt(0);
    }
  }

  void _drainEarlyIce(String callId) {
    final list = _earlyIceByCall.remove(callId);
    if (list == null || list.isEmpty) return;
    for (final data in list) {
      unawaited(_handleIce(data));
    }
  }

  void _flushOutgoingIceQueue() {
    if (_iceFlushInProgress || _outgoingIceQueue.isEmpty) return;
    _iceFlushInProgress = true;
    unawaited(() async {
      try {
        while (_outgoingIceQueue.isNotEmpty && _session != null) {
          final payload = Map<String, dynamic>.from(_outgoingIceQueue.first);
          try {
            await _sendSignal('call_ice', payload);
            _outgoingIceQueue.removeFirst();
            // Small delay to avoid flooding the TCP buffer.
            await Future<void>.delayed(const Duration(milliseconds: 5));
          } catch (e) {
            _log('ice flush send error: $e');
            _iceFlushTimer?.cancel();
            _iceFlushTimer = Timer(const Duration(milliseconds: 250), () {
              _flushOutgoingIceQueue();
            });
            break;
          }
        }
      } finally {
        _iceFlushInProgress = false;
        // Re-check: candidates may have arrived while we were flushing.
        if (_outgoingIceQueue.isNotEmpty && _session != null) {
          _iceFlushTimer?.cancel();
          _iceFlushTimer = Timer(const Duration(milliseconds: 10), () {
            _flushOutgoingIceQueue();
          });
        }
      }
    }());
  }

  void _log(String msg) {
    final line = '${DateTime.now().toIso8601String()} $msg';
    _eventLog.addLast(line);
    while (_eventLog.length > 200) {
      _eventLog.removeFirst();
    }
    debugPrint('[CallService] $line');
  }
}
