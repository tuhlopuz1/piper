import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat.dart';

/// Универсальный аватар — цветной круг с инициалами или иконкой группы.
class AppAvatar extends StatelessWidget {
  final AvatarStyle style;
  final String initials;
  final double size;
  final bool isGroup;

  const AppAvatar({
    super.key,
    required this.style,
    required this.initials,
    this.size = 48,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            style.color.withValues(alpha: 0.75),
            style.color,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: style.color.withValues(alpha: 0.3),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: isGroup
          ? Icon(Icons.group_rounded, color: Colors.white, size: size * 0.44)
          : Center(
              child: Text(
                initials.length > 2 ? initials.substring(0, 2) : initials,
                style: GoogleFonts.inter(
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
    );
  }
}
