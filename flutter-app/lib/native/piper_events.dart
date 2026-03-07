/// Event types received from the Go backend via FFI callback.
library;

class PiperEvent {
  final String type; // "message", "peer", "group", "transfer"

  // Message fields
  final String? msgId;
  final String? msgType;
  final String? peerId;
  final String? peerName;
  final String? content;
  final String? to;
  final String? groupId;
  final String? groupName;
  final int? timestamp;

  // Peer event fields
  final String? peerState; // "joined", "left"

  // Group event fields
  final String? groupEvent; // "created", "member_joined", "member_left", "deleted"
  final List<String>? members;

  // Transfer fields
  final String? transferId;
  final String? transferKind; // "offered","started","progress","completed","failed"
  final String? fileName;
  final int? fileSize;
  final bool? sending;
  final int? progress;
  final String? transferError;

  const PiperEvent({
    required this.type,
    this.msgId,
    this.msgType,
    this.peerId,
    this.peerName,
    this.content,
    this.to,
    this.groupId,
    this.groupName,
    this.timestamp,
    this.peerState,
    this.groupEvent,
    this.members,
    this.transferId,
    this.transferKind,
    this.fileName,
    this.fileSize,
    this.sending,
    this.progress,
    this.transferError,
  });

  factory PiperEvent.fromJson(Map<String, dynamic> json) {
    return PiperEvent(
      type: json['type'] as String,
      msgId: json['msg_id'] as String?,
      msgType: json['msg_type'] as String?,
      peerId: json['peer_id'] as String?,
      peerName: json['peer_name'] as String?,
      content: json['content'] as String?,
      to: json['to'] as String?,
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      timestamp: json['ts'] as int?,
      peerState: json['peer_state'] as String?,
      groupEvent: json['group_event'] as String?,
      members: (json['members'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      transferId: json['transfer_id'] as String?,
      transferKind: json['transfer_kind'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      sending: json['sending'] as bool?,
      progress: json['progress'] as int?,
      transferError: json['transfer_error'] as String?,
    );
  }

  bool get isMessage => type == 'message';
  bool get isPeer => type == 'peer';
  bool get isGroup => type == 'group';
  bool get isTransfer => type == 'transfer';
  bool get isCall => type == 'call';
}

class PeerInfo {
  final String id;
  final String name;
  final String displayName;
  final String state; // "connecting", "connected", "disconnected"

  const PeerInfo({
    required this.id,
    required this.name,
    required this.displayName,
    required this.state,
  });

  factory PeerInfo.fromJson(Map<String, dynamic> json) {
    return PeerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      state: json['state'] as String,
    );
  }

  bool get isConnected => state == 'connected';
}

/// DHT peer record — mirrors Go's core.PeerRecord.
/// Used for BLE / WiFi Direct peer exchange.
class PeerRecord {
  final String id;
  final String name;
  final String ip;
  final int port;

  const PeerRecord({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
  });

  factory PeerRecord.fromJson(Map<String, dynamic> json) {
    return PeerRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
      };
}

class GroupInfo {
  final String id;
  final String name;
  final List<String> members;

  const GroupInfo({
    required this.id,
    required this.name,
    required this.members,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> json) {
    return GroupInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      members: (json['members'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );
  }
}
