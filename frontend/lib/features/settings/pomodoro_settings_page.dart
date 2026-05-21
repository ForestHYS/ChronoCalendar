import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/parse_minutes.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_card.dart';

class PomodoroSettingsPage extends ConsumerStatefulWidget {
  const PomodoroSettingsPage({super.key});

  @override
  ConsumerState<PomodoroSettingsPage> createState() => _PomodoroSettingsPageState();
}

class _PomodoroSettingsPageState extends ConsumerState<PomodoroSettingsPage> {
  late int _focusSec;
  late int _restSec;
  late bool _wake;

  @override
  void initState() {
    super.initState();
    final s = ref.read(pomodoroSettingsRepositoryProvider);
    _focusSec = s.focusSeconds;
    _restSec = s.restSeconds;
    _wake = s.wakelockWhileRunning;
  }

  Future<void> _persist() async {
    final r = ref.read(pomodoroSettingsRepositoryProvider);
    await r.setFocusSeconds(_focusSec);
    await r.setRestSeconds(_restSec);
    await r.setWakelockWhileRunning(_wake);
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    if (s == 0) return '$m 分钟';
    return '$m 分 $s 秒';
  }

  Future<void> _pickFocus() async {
    final c = TextEditingController(text: '${_focusSec ~/ 60}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('专注时长（分钟）'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '1–180（十进制分钟）'),
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('取消')),
          OutlinedButton(
            onPressed: () {
              final m = parseDecimalMinutes(c.text, min: 1, max: 180) ?? 25;
              setState(() => _focusSec = m * 60);
              ctx.pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    await _persist();
    setState(() {});
  }

  Future<void> _pickRest() async {
    final c = TextEditingController(text: '${_restSec ~/ 60}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('休息时长（分钟）'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '1–120（十进制分钟）'),
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('取消')),
          OutlinedButton(
            onPressed: () {
              final m = parseDecimalMinutes(c.text, min: 1, max: 120) ?? 5;
              setState(() => _restSec = m * 60);
              ctx.pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    await _persist();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('番茄钟设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTile(
                  title: const Text('默认专注时长'),
                  subtitle: Text(_fmt(_focusSec)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickFocus,
                ),
                const Divider(height: 1, color: AppColors.outline),
                ListTile(
                  title: const Text('休息时长'),
                  subtitle: Text(_fmt(_restSec)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickRest,
                ),
                const Divider(height: 1, color: AppColors.outline),
                SwitchListTile(
                  title: const Text('计时中保持屏幕常亮'),
                  subtitle: const Text('专注/休息倒计时运行期间'),
                  value: _wake,
                  onChanged: (v) async {
                    setState(() => _wake = v);
                    await _persist();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
