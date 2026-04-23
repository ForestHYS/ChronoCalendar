import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/tag.dart';
import 'compact_task_tag_strip.dart';

/// 标题与标签同一行：标签紧跟标题末尾，不占满整行右侧。
class TitleWithTagsRow extends StatelessWidget {
  const TitleWithTagsRow({
    super.key,
    required this.title,
    required this.tags,
    required this.titleStyle,
  });

  final String title;
  final List<Tag> tags;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (tags.isEmpty) {
          return Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          );
        }
        final tagSlot = (c.maxWidth * 0.34).clamp(70.0, 128.0);
        final titleMax = math.max(36.0, c.maxWidth - 6 - tagSlot);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: titleMax),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: tagSlot,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CompactTaskTagStrip(tags: tags),
              ),
            ),
          ],
        );
      },
    );
  }
}
