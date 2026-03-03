import 'dart:ffi';
import 'dart:io' show Platform;

// C function signatures (as defined in bridge.go)
typedef _CreateNodeC = Int32 Function(Pointer<Utf8> name);
typedef _CreateNodeDart = int Function(Pointer<Utf8> name);

typedef _StartNodeC = Pointer<Utf8> Function(Int32 handle);
typedef _StartNodeDart = Pointer<Utf8> Function(int handle);

typedef _StopNodeC = Void Function(Int32 handle);
typedef _StopNodeDart = void Function(int handle);

typedef _NodeIDC = Pointer<Utf8> Function(Int32 handle);
typedef _NodeIDDart = Pointer<Utf8> Function(int handle);

typedef _NodeNameC = Pointer<Utf8> Function(Int32 handle);
typedef _NodeNameDart = Pointer<Utf8> Function(int handle);

typedef _SendC = Void Function(Int32 handle, Pointer<Utf8> text, Pointer<Utf8> toPeerID);
typedef _SendDart = void Function(int handle, Pointer<Utf8> text, Pointer<Utf8> toPeerID);

typedef _SendGroupC = Void Function(Int32 handle, Pointer<Utf8> text, Pointer<Utf8> groupID);
typedef _SendGroupDart = void Function(int handle, Pointer<Utf8> text, Pointer<Utf8> groupID);

typedef _SendFileC = Pointer<Utf8> Function(Int32 handle, Pointer<Utf8> peerID, Pointer<Utf8> filePath);
typedef _SendFileDart = Pointer<Utf8> Function(int handle, Pointer<Utf8> peerID, Pointer<Utf8> filePath);

typedef _SendFileToGroupC = Pointer<Utf8> Function(Int32 handle, Pointer<Utf8> groupID, Pointer<Utf8> filePath);
typedef _SendFileToGroupDart = Pointer<Utf8> Function(int handle, Pointer<Utf8> groupID, Pointer<Utf8> filePath);

typedef _CreateGroupC = Pointer<Utf8> Function(Int32 handle, Pointer<Utf8> name);
typedef _CreateGroupDart = Pointer<Utf8> Function(int handle, Pointer<Utf8> name);

typedef _InviteToGroupC = Void Function(Int32 handle, Pointer<Utf8> groupID, Pointer<Utf8> peerID);
typedef _InviteToGroupDart = void Function(int handle, Pointer<Utf8> groupID, Pointer<Utf8> peerID);

typedef _LeaveGroupC = Void Function(Int32 handle, Pointer<Utf8> groupID);
typedef _LeaveGroupDart = void Function(int handle, Pointer<Utf8> groupID);

typedef _ListPeersC = Pointer<Utf8> Function(Int32 handle);
typedef _ListPeersDart = Pointer<Utf8> Function(int handle);

typedef _ListGroupsC = Pointer<Utf8> Function(Int32 handle);
typedef _ListGroupsDart = Pointer<Utf8> Function(int handle);

typedef EventCallbackC = Void Function(Pointer<Utf8> eventJSON);
typedef _SetEventCallbackC = Void Function(Int32 handle, Pointer<NativeFunction<EventCallbackC>> cb);
typedef _SetEventCallbackDart = void Function(int handle, Pointer<NativeFunction<EventCallbackC>> cb);

typedef _FreeStringC = Void Function(Pointer<Utf8> s);
typedef _FreeStringDart = void Function(Pointer<Utf8> s);

class PiperBindings {
  late final DynamicLibrary _lib;

  late final _CreateNodeDart createNode;
  late final _StartNodeDart startNode;
  late final _StopNodeDart stopNode;
  late final _NodeIDDart nodeID;
  late final _NodeNameDart nodeName;
  late final _SendDart send;
  late final _SendGroupDart sendGroup;
  late final _SendFileDart sendFile;
  late final _SendFileToGroupDart sendFileToGroup;
  late final _CreateGroupDart createGroup;
  late final _InviteToGroupDart inviteToGroup;
  late final _LeaveGroupDart leaveGroup;
  late final _ListPeersDart listPeers;
  late final _ListGroupsDart listGroups;
  late final _SetEventCallbackDart setEventCallback;
  late final _FreeStringDart freeString;

  PiperBindings({String? libraryPath}) {
    _lib = DynamicLibrary.open(libraryPath ?? _defaultLibPath());

    createNode = _lib
        .lookupFunction<_CreateNodeC, _CreateNodeDart>('PiperCreateNode');
    startNode = _lib
        .lookupFunction<_StartNodeC, _StartNodeDart>('PiperStartNode');
    stopNode = _lib
        .lookupFunction<_StopNodeC, _StopNodeDart>('PiperStopNode');
    nodeID = _lib
        .lookupFunction<_NodeIDC, _NodeIDDart>('PiperNodeID');
    nodeName = _lib
        .lookupFunction<_NodeNameC, _NodeNameDart>('PiperNodeName');
    send = _lib
        .lookupFunction<_SendC, _SendDart>('PiperSend');
    sendGroup = _lib
        .lookupFunction<_SendGroupC, _SendGroupDart>('PiperSendGroup');
    sendFile = _lib
        .lookupFunction<_SendFileC, _SendFileDart>('PiperSendFile');
    sendFileToGroup = _lib
        .lookupFunction<_SendFileToGroupC, _SendFileToGroupDart>('PiperSendFileToGroup');
    createGroup = _lib
        .lookupFunction<_CreateGroupC, _CreateGroupDart>('PiperCreateGroup');
    inviteToGroup = _lib
        .lookupFunction<_InviteToGroupC, _InviteToGroupDart>('PiperInviteToGroup');
    leaveGroup = _lib
        .lookupFunction<_LeaveGroupC, _LeaveGroupDart>('PiperLeaveGroup');
    listPeers = _lib
        .lookupFunction<_ListPeersC, _ListPeersDart>('PiperListPeers');
    listGroups = _lib
        .lookupFunction<_ListGroupsC, _ListGroupsDart>('PiperListGroups');
    setEventCallback = _lib
        .lookupFunction<_SetEventCallbackC, _SetEventCallbackDart>('PiperSetEventCallback');
    freeString = _lib
        .lookupFunction<_FreeStringC, _FreeStringDart>('PiperFreeString');
  }

  static String _defaultLibPath() {
    if (Platform.isWindows) return 'libpiper.dll';
    if (Platform.isLinux) return 'libpiper.so';
    if (Platform.isMacOS) return 'libpiper.dylib';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
