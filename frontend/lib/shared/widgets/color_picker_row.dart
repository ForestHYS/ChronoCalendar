import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'tag_color_palette.dart';

/// 颜色选择行；选中态会随点击即时刷新。
class ColorPickerRow extends StatefulWidget {
  const ColorPickerRow({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<ColorPickerRow> createState() => _ColorPickerRowState();
}

class _ColorPickerRowState extends State<ColorPickerRow> {
  late Color _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  void didUpdateWidget(ColorPickerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _selected = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in TagColorPalette.colors)
          InkWell(
            onTap: () {
              setState(() => _selected = c);
              widget.onChanged(c);
            },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == _selected ? AppColors.onSurface : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: c == _selected
                    ? [
                        BoxShadow(
                          color: AppColors.onSurface.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
