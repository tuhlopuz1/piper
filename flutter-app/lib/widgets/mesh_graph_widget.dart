import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../native/piper_events.dart';
import '../theme/app_theme.dart';

class MeshGraphWidget extends StatelessWidget {
  final MeshTopology topology;

  const MeshGraphWidget({super.key, required this.topology});

  @override
  Widget build(BuildContext context) {
    if (topology.nodes.isEmpty) {
      return _placeholder('Нет данных топологии');
    }
    return SizedBox(
      width: 260,
      height: 260,
      child: CustomPaint(
        painter: _MeshGraphPainter(topology: topology),
      ),
    );
  }

  Widget _placeholder(String text) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.bgSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.mutedForeground,
        ),
      ),
    );
  }
}

class _MeshGraphPainter extends CustomPainter {
  final MeshTopology topology;

  _MeshGraphPainter({required this.topology});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final localId = topology.localId;
    final nodes = topology.nodes;
    final byId = {for (final n in nodes) n.id: n};
    final positions = <String, Offset>{};

    final localNode = nodes.firstWhere(
      (n) => n.id == localId || n.isSelf,
      orElse: () => nodes.first,
    );
    positions[localNode.id] = center;

    final others = nodes.where((n) => n.id != localNode.id).toList();
    for (var i = 0; i < others.length; i++) {
      final a = (2 * math.pi * i / math.max(others.length, 1)) - math.pi / 2;
      positions[others[i].id] = Offset(
        center.dx + radius * math.cos(a),
        center.dy + radius * math.sin(a),
      );
    }

    final directPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.65)
      ..strokeWidth = 1.4;
    final relayPaint = Paint()
      ..color = AppColors.online.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;

    for (final e in topology.edges) {
      final from = positions[e.from];
      final to = positions[e.to];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, e.kind == 'relay' ? relayPaint : directPaint);
    }

    for (final node in nodes) {
      final p = positions[node.id];
      if (p == null) continue;
      final color = node.isSelf
          ? AppColors.primary
          : node.isRelay
              ? AppColors.online
              : AppColors.mutedForeground;
      final r = node.isSelf ? 12.0 : 10.0;
      canvas.drawCircle(p, r, Paint()..color = color);

      final label = _abbr(node.name.isNotEmpty ? node.name : node.id);
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(p.dx - text.width / 2, p.dy - text.height / 2));
    }
  }

  String _abbr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(' ');
    if (parts.length >= 2) {
      return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(0, 2)).toUpperCase();
  }

  @override
  bool shouldRepaint(covariant _MeshGraphPainter oldDelegate) {
    return oldDelegate.topology != topology;
  }
}
