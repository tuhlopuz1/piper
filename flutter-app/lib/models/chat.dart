import 'package:flutter/material.dart';

// ─── Avatar styles ───────────────────────────────────────────────────────────

enum AvatarStyle { violet, cyan, rose, orange, emerald, blue, amber, indigo }

extension AvatarStyleX on AvatarStyle {
  Color get color => const {
    AvatarStyle.violet:  Color(0xFF7C3AED),
    AvatarStyle.cyan:    Color(0xFF06B6D4),
    AvatarStyle.rose:    Color(0xFFE11D48),
    AvatarStyle.orange:  Color(0xFFF97316),
    AvatarStyle.emerald: Color(0xFF10B981),
    AvatarStyle.blue:    Color(0xFF3B82F6),
    AvatarStyle.amber:   Color(0xFFF59E0B),
    AvatarStyle.indigo:  Color(0xFF6366F1),
  }[this]!;

  String get emoji => const {
    AvatarStyle.violet:  '💜',
    AvatarStyle.cyan:    '🩵',
    AvatarStyle.rose:    '🌸',
    AvatarStyle.orange:  '🔶',
    AvatarStyle.emerald: '💚',
    AvatarStyle.blue:    '💙',
    AvatarStyle.amber:   '⭐',
    AvatarStyle.indigo:  '🔷',
  }[this]!;
}

// ─── Message type ─────────────────────────────────────────────────────────────

enum MessageType { text, photo, voice, file, call }

// ─── Chat model ──────────────────────────────────────────────────────────────

class Chat {
  final String id;
  final String name;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final AvatarStyle avatarStyle;
  final String initials;
  final bool isOnline;
  final MessageType lastMessageType;
  final int memberCount;

  const Chat({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isGroup,
    required this.avatarStyle,
    required this.initials,
    required this.isOnline,
    required this.lastMessageType,
    this.memberCount = 0,
  });
}

// ─── Contact model ───────────────────────────────────────────────────────────

class Contact {
  final String id;
  final String name;
  final AvatarStyle avatarStyle;
  final String initials;
  final bool isOnline;
  final String address;
  final bool isRelay;
  final String? relayPeerName;

  const Contact({
    required this.id,
    required this.name,
    required this.avatarStyle,
    required this.initials,
    required this.isOnline,
    required this.address,
    this.isRelay = false,
    this.relayPeerName,
  });
}

// ─── Mock data ───────────────────────────────────────────────────────────────

final List<Chat> mockChats = [
  Chat(
    id: '1',
    name: 'Alex K.',
    lastMessage: 'Отправил файл presentation.pdf',
    lastMessageTime: DateTime.now().subtract(const Duration(minutes: 12)),
    unreadCount: 2,
    isGroup: false,
    avatarStyle: AvatarStyle.violet,
    initials: 'AK',
    isOnline: true,
    lastMessageType: MessageType.file,
  ),
  Chat(
    id: '3',
    name: 'Maria S.',
    lastMessage: 'Голосовое сообщение',
    lastMessageTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 15)),
    unreadCount: 0,
    isGroup: false,
    avatarStyle: AvatarStyle.rose,
    initials: 'MS',
    isOnline: true,
    lastMessageType: MessageType.voice,
  ),
  Chat(
    id: '4',
    name: 'Dmitry P.',
    lastMessage: 'Ok, понял!',
    lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
    unreadCount: 0,
    isGroup: false,
    avatarStyle: AvatarStyle.blue,
    initials: 'DP',
    isOnline: false,
    lastMessageType: MessageType.text,
  ),
  Chat(
    id: '6',
    name: 'Nastya V.',
    lastMessage: 'Привет, как дела?',
    lastMessageTime: DateTime.now().subtract(const Duration(hours: 5)),
    unreadCount: 1,
    isGroup: false,
    avatarStyle: AvatarStyle.amber,
    initials: 'NV',
    isOnline: false,
    lastMessageType: MessageType.text,
  ),
];

final List<Contact> mockContacts = [
  Contact(id: '1', name: 'Alex K.',   avatarStyle: AvatarStyle.violet,  initials: 'AK', isOnline: true,  address: '192.168.1.12'),
  Contact(id: '2', name: 'Maria S.',  avatarStyle: AvatarStyle.rose,    initials: 'MS', isOnline: true,  address: '192.168.1.15'),
  Contact(id: '3', name: 'Dmitry P.', avatarStyle: AvatarStyle.blue,    initials: 'DP', isOnline: false, address: '192.168.1.21'),
  Contact(id: '4', name: 'Nastya V.', avatarStyle: AvatarStyle.amber,   initials: 'NV', isOnline: false, address: '192.168.1.34'),
  Contact(id: '5', name: 'Igor M.',   avatarStyle: AvatarStyle.emerald, initials: 'IM', isOnline: false, address: '192.168.1.47'),
];
