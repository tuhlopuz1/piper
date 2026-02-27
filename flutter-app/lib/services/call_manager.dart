import 'package:flutter/material.dart';
import '../models/chat.dart';

class CallManager {
  static final CallManager instance = CallManager._();
  CallManager._();

  final activeCall = ValueNotifier<Chat?>(null);

  void startCall(Chat chat) => activeCall.value = chat;
  void endCall() => activeCall.value = null;
}
