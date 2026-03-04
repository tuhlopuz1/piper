import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

import '../../services/piper_service.dart';
import '../../theme/app_theme.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = context.read<PiperService>();
    final dir = Directory(svc.downloadsDir);
    if (!await dir.exists()) {
      setState(() { _files = []; _loading = false; });
      return;
    }
    final entities = await dir.list().where((e) => e is File).toList();
    entities.sort((a, b) {
      final sa = (a as File).statSync();
      final sb = (b as File).statSync();
      return sb.modified.compareTo(sa.modified);
    });
    setState(() { _files = entities; _loading = false; });
  }

  Future<void> _delete(FileSystemEntity f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSubtle,
        title: Text('Удалить файл?', style: GoogleFonts.inter(color: AppColors.foreground)),
        content: Text(
          f.path.split(Platform.pathSeparator).last,
          style: GoogleFonts.inter(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить', style: TextStyle(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await f.delete();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          // ── AppBar ────────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 8, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: AppColors.foreground,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Загрузки',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AppColors.mutedForeground,
                  onPressed: () { setState(() => _loading = true); _load(); },
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _FileCard(
                          file: _files[i] as File,
                          onOpen: () => OpenFile.open(_files[i].path),
                          onDelete: () => _delete(_files[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── File card ──────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final File file;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  const _FileCard({required this.file, required this.onOpen, required this.onDelete});

  String get _name => file.path.split(Platform.pathSeparator).last;
  String get _ext  => _name.contains('.') ? _name.split('.').last.toUpperCase() : '?';

  String _sizeStr(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get _icon {
    switch (_ext.toLowerCase()) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Icons.image_outlined;
      case 'mp4': case 'mov': case 'avi': case 'mkv': return Icons.videocam_outlined;
      case 'mp3': case 'wav': case 'ogg': case 'm4a': return Icons.audiotrack_outlined;
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'zip': case 'rar': case '7z': case 'tar': return Icons.folder_zip_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stat = file.statSync();
    final date = stat.modified;
    final dateStr =
        '${date.day.toString().padLeft(2,'0')}.${date.month.toString().padLeft(2,'0')}.${date.year}';

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: AppColors.primaryLight, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_sizeStr(stat.size)} · $dateStr',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppColors.mutedForeground,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_outlined, size: 56, color: AppColors.mutedForeground.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'Нет загрузок',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Полученные файлы появятся здесь',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.mutedForeground.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
