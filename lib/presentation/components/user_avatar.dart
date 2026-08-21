import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Circular user avatar that prefers an image URL and falls back to the
/// user's initials on a branded dark tile (or when the image fails to load).
///
/// Used by the DM list, the DM chat header and the Profile header so the
/// avatar rendering stays consistent across the app.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color accentColor;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 20,
    this.accentColor,
  });

  /// Resolves the accent (falls back to the theme accent when not provided).
  Color get _accent => accentColor ?? NOC.accent;

  String get _initials {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildInitialsFallback(),
        ),
      );
    }
    return _buildInitialsFallback();
  }

  Widget _buildInitialsFallback() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: NOC.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(color: _accent.withOpacity(0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: _accent,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
