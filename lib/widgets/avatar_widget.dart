import 'package:flutter/material.dart';

class AvatarWidget extends StatelessWidget {
  final String userId;
  final double size;
  final String? imageUrl;

  const AvatarWidget({
    super.key,
    required this.userId,
    this.size = 40,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        userId.isNotEmpty ? userId.substring(0, 1).toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _colorFromId(userId),
      backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
          ? NetworkImage(imageUrl!)
          : null,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text(initial,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.4))
          : null,
    );
  }

  Color _colorFromId(String id) {
    final colors = [
      const Color(0xFF1877F2),
      const Color(0xFF42B72A),
      const Color(0xFFE4405F),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
    ];
    int hash = 0;
    for (final c in id.codeUnits) hash = (hash * 31 + c) & 0xFFFFFFFF;
    return colors[hash % colors.length];
  }
}
