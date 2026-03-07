import 'package:flutter/material.dart';
import 'chat.dart';

enum MsgType { text, image, file, voice, call }

enum CallResult { answered, missed, rejected }

class Message {
  final String id;
  final bool isMe;
  final String? senderName;
  final Color? senderColor;
  final MsgType type;

  // text
  final String? text;

  // image (mock — colored container)
  final Color? imageColor;
  final double imageAspect; // width / height

  // file
  final String? fileName;
  final String? fileExt;
  final int? fileSize; // bytes
  final String? filePath; // local path for opening

  // voice
  final int? voiceDuration; // seconds

  // call
  final int? callDuration; // seconds (0 for missed/rejected)
  final bool? callIsVideo;
  final CallResult? callResult; // answered, missed, rejected

  final DateTime time;
  final bool delivered;

  const Message({
    required this.id,
    required this.isMe,
    this.senderName,
    this.senderColor,
    required this.type,
    this.text,
    this.imageColor,
    this.imageAspect = 4 / 3,
    this.fileName,
    this.fileExt,
    this.fileSize,
    this.filePath,
    this.voiceDuration,
    this.callDuration,
    this.callIsVideo,
    this.callResult,
    required this.time,
    this.delivered = true,
  });

  Message copyWith({
    String? id,
    bool? isMe,
    String? senderName,
    Color? senderColor,
    MsgType? type,
    String? text,
    Color? imageColor,
    double? imageAspect,
    String? fileName,
    String? fileExt,
    int? fileSize,
    String? filePath,
    int? voiceDuration,
    int? callDuration,
    bool? callIsVideo,
    CallResult? callResult,
    DateTime? time,
    bool? delivered,
  }) {
    return Message(
      id: id ?? this.id,
      isMe: isMe ?? this.isMe,
      senderName: senderName ?? this.senderName,
      senderColor: senderColor ?? this.senderColor,
      type: type ?? this.type,
      text: text ?? this.text,
      imageColor: imageColor ?? this.imageColor,
      imageAspect: imageAspect ?? this.imageAspect,
      fileName: fileName ?? this.fileName,
      fileExt: fileExt ?? this.fileExt,
      fileSize: fileSize ?? this.fileSize,
      filePath: filePath ?? this.filePath,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      callDuration: callDuration ?? this.callDuration,
      callIsVideo: callIsVideo ?? this.callIsVideo,
      callResult: callResult ?? this.callResult,
      time: time ?? this.time,
      delivered: delivered ?? this.delivered,
    );
  }
}

// ─── Mock message factory ─────────────────────────────────────────────────────

List<Message> getMockMessages(Chat chat) {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));

  if (chat.isGroup) {
    return [
      Message(
          id: 'm01',
          isMe: false,
          senderName: 'Alex K.',
          senderColor: AvatarStyle.violet.color,
          type: MsgType.text,
          text: 'Всем привет! Начинаем стендап?',
          time: yesterday.copyWith(hour: 9, minute: 0),
          delivered: true),
      Message(
          id: 'm02',
          isMe: false,
          senderName: 'Maria S.',
          senderColor: AvatarStyle.rose.color,
          type: MsgType.text,
          text: 'Да, готова!',
          time: yesterday.copyWith(hour: 9, minute: 1),
          delivered: true),
      Message(
          id: 'm03',
          isMe: true,
          type: MsgType.text,
          text: 'Тоже здесь',
          time: yesterday.copyWith(hour: 9, minute: 2),
          delivered: true),
      Message(
          id: 'm04',
          isMe: false,
          senderName: 'Alex K.',
          senderColor: AvatarStyle.violet.color,
          type: MsgType.file,
          fileName: 'sprint_plan.pdf',
          fileExt: 'pdf',
          fileSize: 1840000,
          time: yesterday.copyWith(hour: 9, minute: 5),
          delivered: true),
      Message(
          id: 'm05',
          isMe: false,
          senderName: 'Maria S.',
          senderColor: AvatarStyle.rose.color,
          type: MsgType.image,
          imageColor: const Color(0xFF3B82F6),
          imageAspect: 16 / 9,
          time: yesterday.copyWith(hour: 9, minute: 15),
          delivered: true),
      Message(
          id: 'm06',
          isMe: true,
          type: MsgType.text,
          text: 'Видел, спасибо. Давайте встретимся в 15:00 в переговорке?',
          time: now.copyWith(hour: 13, minute: 20),
          delivered: true),
      Message(
          id: 'm07',
          isMe: false,
          senderName: 'Alex K.',
          senderColor: AvatarStyle.violet.color,
          type: MsgType.text,
          text: 'Ок, буду',
          time: now.copyWith(hour: 13, minute: 22),
          delivered: true),
      Message(
          id: 'm08',
          isMe: false,
          senderName: 'Maria S.',
          senderColor: AvatarStyle.rose.color,
          type: MsgType.voice,
          voiceDuration: 8,
          time: now.copyWith(hour: 13, minute: 23),
          delivered: true),
    ];
  } else {
    return [
      Message(
          id: 'p01',
          isMe: false,
          senderName: chat.name,
          senderColor: chat.avatarStyle.color,
          type: MsgType.text,
          text: 'Привет! Скинешь файлы с презентацией?',
          time: now.copyWith(hour: 11, minute: 0),
          delivered: true),
      Message(
          id: 'p02',
          isMe: true,
          type: MsgType.text,
          text: 'Да, секунду',
          time: now.copyWith(hour: 11, minute: 1),
          delivered: true),
      Message(
          id: 'p03',
          isMe: true,
          type: MsgType.file,
          fileName: 'presentation.pdf',
          fileExt: 'pdf',
          fileSize: 2400000,
          time: now.copyWith(hour: 11, minute: 2),
          delivered: true),
      Message(
          id: 'p04',
          isMe: false,
          senderName: chat.name,
          senderColor: chat.avatarStyle.color,
          type: MsgType.text,
          text: 'Отлично, спасибо! А скриншоты интерфейса есть?',
          time: now.copyWith(hour: 11, minute: 4),
          delivered: true),
      Message(
          id: 'p05',
          isMe: true,
          type: MsgType.image,
          imageColor: const Color(0xFF7C3AED),
          imageAspect: 16 / 9,
          time: now.copyWith(hour: 11, minute: 5),
          delivered: true),
      Message(
          id: 'p06',
          isMe: false,
          senderName: chat.name,
          senderColor: chat.avatarStyle.color,
          type: MsgType.voice,
          voiceDuration: 12,
          time: now.copyWith(hour: 11, minute: 10),
          delivered: true),
      Message(
          id: 'p07',
          isMe: true,
          type: MsgType.text,
          text: 'Голосовое не слышу, напиши',
          time: now.copyWith(hour: 11, minute: 11),
          delivered: true),
      Message(
          id: 'p08',
          isMe: false,
          senderName: chat.name,
          senderColor: chat.avatarStyle.color,
          type: MsgType.text,
          text: 'Встретимся в 15:00 в переговорке?',
          time: now.copyWith(hour: 11, minute: 12),
          delivered: true),
      Message(
          id: 'p09',
          isMe: true,
          type: MsgType.text,
          text: 'Да, буду',
          time: now.copyWith(hour: 11, minute: 13),
          delivered: true),
    ];
  }
}

extension _DateExt on DateTime {
  DateTime copyWith({int? hour, int? minute}) =>
      DateTime(year, month, day, hour ?? this.hour, minute ?? this.minute);
}
