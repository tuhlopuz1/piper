import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/message.dart';
import 'log_service.dart';

/// Singleton service that owns the SQLite database for chat/message persistence.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    try {
      // Desktop platforms don't have a native sqflite plugin — use FFI.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dbPath = p.join(await getDatabasesPath(), 'piper.db');
      LogService.instance.info('[DB] opening $dbPath');

      _db = await openDatabase(
        dbPath,
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE messages (
              id             TEXT    PRIMARY KEY,
              chat_id        TEXT    NOT NULL,
              is_me          INTEGER NOT NULL,
              sender_name    TEXT,
              sender_color   INTEGER,
              type           TEXT    NOT NULL,
              text           TEXT,
              file_name      TEXT,
              file_ext       TEXT,
              file_path      TEXT,
              file_size      INTEGER,
              voice_duration INTEGER,
              call_duration  INTEGER,
              call_is_video  INTEGER,
              call_result    TEXT,
              time           INTEGER NOT NULL,
              delivered      INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_messages_chat ON messages(chat_id, time)',
          );
          await db.execute('''
            CREATE TABLE chats (
              id           TEXT    PRIMARY KEY,
              name         TEXT    NOT NULL DEFAULT '',
              unread_count INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE chats ADD COLUMN name TEXT NOT NULL DEFAULT ''",
            );
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE messages ADD COLUMN call_duration INTEGER');
            await db.execute('ALTER TABLE messages ADD COLUMN call_is_video INTEGER');
            await db.execute('ALTER TABLE messages ADD COLUMN call_result TEXT');
          }
        },
      );

      LogService.instance.info('[DB] ready');
    } catch (e, st) {
      LogService.instance.error('[DB] init failed: $e', detail: st.toString());
      rethrow;
    }
  }

  Database get _database {
    assert(_db != null, 'DatabaseService.init() must be called before use');
    return _db!;
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<void> insertMessage(String chatId, Message msg) async {
    await _database.insert(
      'messages',
      {
        'id': msg.id,
        'chat_id': chatId,
        'is_me': msg.isMe ? 1 : 0,
        'sender_name': msg.senderName,
        'sender_color': msg.senderColor?.toARGB32(),
        'type': msg.type.name,
        'text': msg.text,
        'file_name': msg.fileName,
        'file_ext': msg.fileExt,
        'file_path': msg.filePath,
        'file_size': msg.fileSize,
        'voice_duration': msg.voiceDuration,
        'call_duration': msg.callDuration,
        'call_is_video': msg.callIsVideo == null ? null : (msg.callIsVideo! ? 1 : 0),
        'call_result': msg.callResult?.name,
        'time': msg.time.millisecondsSinceEpoch,
        'delivered': msg.delivered ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loads all messages grouped by chat_id (oldest first within each chat).
  Future<Map<String, List<Message>>> getAllMessages() async {
    final rows = await _database.query('messages', orderBy: 'time ASC');
    final result = <String, List<Message>>{};
    for (final row in rows) {
      final chatId = row['chat_id'] as String;
      result.putIfAbsent(chatId, () => []).add(_rowToMessage(row));
    }
    return result;
  }

  Future<void> markDelivered(String msgId) async {
    await _database.update(
      'messages',
      {'delivered': 1},
      where: 'id = ?',
      whereArgs: [msgId],
    );
  }

  Message _rowToMessage(Map<String, dynamic> row) {
    final colorVal = row['sender_color'] as int?;
    return Message(
      id: row['id'] as String,
      isMe: (row['is_me'] as int) == 1,
      senderName: row['sender_name'] as String?,
      senderColor: colorVal != null ? Color(colorVal) : null,
      type: MsgType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => MsgType.text,
      ),
      text: row['text'] as String?,
      fileName: row['file_name'] as String?,
      fileExt: row['file_ext'] as String?,
      filePath: row['file_path'] as String?,
      fileSize: row['file_size'] as int?,
      voiceDuration: row['voice_duration'] as int?,
      callDuration: row['call_duration'] as int?,
      callIsVideo: row['call_is_video'] != null ? (row['call_is_video'] as int) == 1 : null,
      callResult: row['call_result'] != null
          ? CallResult.values.firstWhere(
              (r) => r.name == row['call_result'],
              orElse: () => CallResult.answered,
            )
          : null,
      time: DateTime.fromMillisecondsSinceEpoch(row['time'] as int),
      delivered: (row['delivered'] as int) == 1,
    );
  }

  // ── Chat names ─────────────────────────────────────────────────────────────

  /// Returns a map of chatId → display name for all known chats.
  Future<Map<String, String>> getChatNames() async {
    final rows = await _database.query('chats');
    return {
      for (final r in rows)
        r['id'] as String: (r['name'] as String?) ?? '',
    };
  }

  /// Persists a chat's display name (upsert). Does not touch unread_count.
  Future<void> upsertChatName(String chatId, String name) async {
    await _database.rawInsert(
      "INSERT INTO chats(id, name, unread_count) VALUES(?, ?, 0) "
      "ON CONFLICT(id) DO UPDATE SET name = excluded.name",
      [chatId, name],
    );
  }

  // ── Unread counts ──────────────────────────────────────────────────────────

  Future<Map<String, int>> getUnreadCounts() async {
    final rows = await _database.query('chats');
    return {
      for (final r in rows) r['id'] as String: r['unread_count'] as int,
    };
  }

  Future<void> incrementUnread(String chatId) async {
    await _database.rawInsert(
      'INSERT INTO chats(id, name, unread_count) VALUES(?, \'\', 1) '
      'ON CONFLICT(id) DO UPDATE SET unread_count = unread_count + 1',
      [chatId],
    );
  }

  Future<void> clearUnread(String chatId) async {
    await _database.rawInsert(
      'INSERT INTO chats(id, name, unread_count) VALUES(?, \'\', 0) '
      'ON CONFLICT(id) DO UPDATE SET unread_count = 0',
      [chatId],
    );
  }
}
