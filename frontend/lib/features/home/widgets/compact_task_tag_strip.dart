import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/tag.dart';

/// 任务标题右侧紧凑标签带；在有限宽度内缩放避免溢出，最多 3 个完整 + 第 4 个渐变示意。
class CompactTaskTagStrip extends StatelessWidget {
  const CompactTaskTagStrip({super.key, required this.tags});

  final List<Tag> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w < 4) return const SizedBox.shrink();
        // 不做 scaleDown：保持标签 pill 尺寸一致，多了则裁剪；右侧渐隐提示还有内容。
        return SizedBox(
          width: w,
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                // 右侧 18px 渐隐，避免“硬切”看不出省略。
                const fade = 18.0;
                final start = ((bounds.width - fade) / bounds.width).clamp(0.0, 1.0);
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  stops: [0.0, start, 1.0],
                ).createShader(bounds);
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: _TagRowInner(tags: tags),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TagRowInner extends StatelessWidget {
  const _TagRowInner({required this.tags});

  final List<Tag> tags;

  @override
  Widget build(BuildContext context) {
    final n = tags.length;
    final children = <Widget>[];
    final fullCount = n > 3 ? 3 : n;
    for (var i = 0; i < fullCount; i++) {
      children.add(_TagPill(tag: tags[i]));
      if (i < fullCount - 1) {
        children.add(const SizedBox(width: 4));
      }
    }
    if (n > 3) {
      children.add(const SizedBox(width: 4));
      children.add(
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0x66FFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: [0.0, 0.45, 1.0],
            ).createShader(bounds);
          },
          child: Opacity(
            opacity: 0.85,
            child: _TagPill(tag: tags[3]),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 40),
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
