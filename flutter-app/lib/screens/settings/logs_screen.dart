import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/log_service.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          // ── App bar ──────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: AppColors.foreground,
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Логи',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  color: AppColors.mutedForeground,
                  tooltip: 'Очистить логи',
                  onPressed: () => LogService.instance.clear(),
                ),
              ],
            ),
          ),

          // ── Log list ──────────────────────────────────────────────────────
          Expanded(
            child: ChangeNotifierProvider.value(
              value: LogService.instance,
              child: Consumer<LogService>(
                builder: (_, svc, __) {
                  final entries = svc.entries.reversed.toList();
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'Нет записей',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 0, color: AppColors.border, thickness: 0.5),
                    itemBuilder: (_, i) => _LogTile(entry: entries[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single log entry tile ────────────────────────────────────────────────────

class _LogTile extends StatefulWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  Color get _levelColor {
    switch (widget.entry.level) {
      case LogLevel.error:   return const Color(0xFFEF4444);
      case LogLevel.warning: return const Color(0xFFF59E0B);
      case LogLevel.info:    return AppColors.mutedForeground;
    }
  }

  IconData get _levelIcon {
    switch (widget.entry.level) {
      case LogLevel.error:   return Icons.error_outline_rounded;
      case LogLevel.warning: return Icons.warning_amber_rounded;
      case LogLevel.info:    return Icons.info_outline_rounded;
    }
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:${t.second.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final hasDetail = e.detail != null && e.detail!.isNotEmpty;

    return GestureDetector(
      onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
      onLongPress: () {
        final text = hasDetail ? '${e.message}\n\n${e.detail}' : e.message;
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Скопировано'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_levelIcon, size: 14, color: _levelColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.message,
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      color: AppColors.foreground,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmt(e.time),
                  style: GoogleFonts.robotoMono(
                    fontSize: 10,
                    color: AppColors.mutedForeground,
                  ),
                ),
                if (hasDetail) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: AppColors.mutedForeground,
                  ),
                ],
              ],
            ),
            if (_expanded && hasDetail) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgBase,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  e.detail!,
                  style: GoogleFonts.robotoMono(
                    fontSize: 10,
                    color: AppColors.mutedForeground,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
