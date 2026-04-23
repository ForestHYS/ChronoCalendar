import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../domain/models/tag.dart';
import '../../shared/widgets/app_card.dart';

class TagManagePage extends ConsumerWidget {
  const TagManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(taskRepositoryProvider);
    final tags = repo.tags;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('编辑标签'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '备选标签',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                ),
                const SizedBox(height: 10),
                for (final t in tags) ...[
                  _TagRow(
                    tag: t,
                    onRename: () => _showRename(context, ref, t),
                    onColor: () => _showRecolor(context, ref, t),
                    onDelete: () => _confirmDelete(context, ref, t),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => _showAdd(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增标签'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showAdd(BuildContext context, WidgetRef ref) async {
    final nameC = TextEditingController();
    Color color = AppColors.chartTagColors[0];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 10),
              _ColorPickerRow(
                initial: color,
                onChanged: (c) => color = c,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => context.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () {
                ref.read(taskRepositoryProvider).addTag(name: nameC.text, color: color);
                context.pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showRename(BuildContext context, WidgetRef ref, Tag tag) async {
    final c = TextEditingController(text: tag.name);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改名称'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          actions: [
            TextButton(onPressed: () => context.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () {
                ref.read(taskRepositoryProvider).renameTag(tag.id, c.text);
                context.pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showRecolor(BuildContext context, WidgetRef ref, Tag tag) async {
    Color color = tag.color;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改颜色'),
          content: _ColorPickerRow(
            initial: color,
            onChanged: (c) => color = c,
          ),
          actions: [
            TextButton(onPressed: () => context.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () {
                ref.read(taskRepositoryProvider).recolorTag(tag.id, color);
                context.pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Tag tag) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除标签？'),
          content: Text('将从任务中移除 “${tag.name}” 标签。'),
          actions: [
            TextButton(onPressed: () => context.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () {
                ref.read(taskRepositoryProvider).deleteTag(tag.id);
                context.pop();
              },
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.onRename,
    required this.onColor,
    required this.onDelete,
  });

  final Tag tag;
  final VoidCallback onRename;
  final VoidCallback onColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppOutlinedBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tag.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
            ),
          ),
          IconButton(
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '改名',
          ),
          IconButton(
            onPressed: onColor,
            icon: const Icon(Icons.palette_outlined, size: 20),
            tooltip: '颜色',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      ...AppColors.chartTagColors,
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.error,
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in colors)
          InkWell(
            onTap: () => onChanged(c),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == initial ? AppColors.onSurface : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

