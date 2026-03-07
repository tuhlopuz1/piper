import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';

class CallQualityIndicator extends StatelessWidget {
  final bool compact;
  const CallQualityIndicator({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallService.instance,
      builder: (context, _) {
        final m = CallService.instance.metrics;
        if (m.quality == CallQuality.unknown) return const SizedBox.shrink();

        return compact ? _CompactIndicator(m: m) : _DetailedIndicator(m: m);
      },
    );
  }
}

class _CompactIndicator extends StatelessWidget {
  final CallMetrics m;
  const _CompactIndicator({required this.m});

  @override
  Widget build(BuildContext context) {
    final color = _qualityColor(m.quality);
    final bars = _qualityBars(m.quality);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++)
          Container(
            width: 4,
            height: 6.0 + (i * 4),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: i < bars ? color : color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          '${m.rttMs.round()} ms',
          style: GoogleFonts.inter(fontSize: 10, color: color),
        ),
      ],
    );
  }
}

class _DetailedIndicator extends StatelessWidget {
  final CallMetrics m;
  const _DetailedIndicator({required this.m});

  @override
  Widget build(BuildContext context) {
    final color = _qualityColor(m.quality);
    final bars = _qualityBars(m.quality);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgSubtle.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Signal bars
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 6.0 + (i * 4),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: i < bars ? color : color.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          // Metrics text
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.rttMs.round()} ms  jitter ${m.jitterMs.toStringAsFixed(1)} ms',
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.mutedForeground),
              ),
              Text(
                'loss ${m.packetLossPercent.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(fontSize: 10, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _qualityColor(CallQuality q) {
  switch (q) {
    case CallQuality.good:
      return AppColors.online;
    case CallQuality.fair:
      return Colors.orange;
    case CallQuality.poor:
      return AppColors.destructive;
    case CallQuality.unknown:
      return AppColors.mutedForeground;
  }
}

int _qualityBars(CallQuality q) {
  switch (q) {
    case CallQuality.good:
      return 3;
    case CallQuality.fair:
      return 2;
    case CallQuality.poor:
      return 1;
    case CallQuality.unknown:
      return 0;
  }
}
