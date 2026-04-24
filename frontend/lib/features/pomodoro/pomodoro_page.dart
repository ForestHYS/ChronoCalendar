import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

class PomodoroPage extends ConsumerStatefulWidget {
  const PomodoroPage({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<PomodoroPage> createState() => _PomodoroPageState();
}

enum _Phase { focus, rest }

class _PomodoroPageState extends ConsumerState<PomodoroPage> {
  Timer? _ticker;
  _Phase _phase = _Phase.focus;
  late int _sessionFocusSeconds;
  late int _restSeconds;
  late bool _wakelockPref;
  late Duration _left;
  bool _running = false;
  /// 一旦按过「开始」则不可再改本轮专注时长。
  bool _sessionLocked = false;

  final AudioPlayer _player = AudioPlayer();
  String? _bgmAsset;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(pomodoroSettingsRepositoryProvider);
    _sessionFocusSeconds = settings.focusSeconds;
    _restSeconds = settings.restSeconds;
    _wakelockPref = settings.wakelockWhileRunning;
    _left = Duration(seconds: _sessionFocusSeconds);
    unawaited(_player.setReleaseMode(ReleaseMode.loop));
    unawaited(_player.setVolume(0.65));
    unawaited(_applyWakeLock());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(WakelockPlus.disable());
    _player.dispose();
    super.dispose();
  }

  Future<void> _applyWakeLock() async {
    final on = _wakelockPref && _running;
    await WakelockPlus.toggle(enable: on);
  }

  Duration get _phaseTotal =>
      _phase == _Phase.focus ? Duration(seconds: _sessionFocusSeconds) : Duration(seconds: _restSeconds);

  double get _progress {
    final t = _phaseTotal.inSeconds;
    if (t <= 0) return 0;
    return 1.0 - (_left.inSeconds / t);
  }

  void _setRunning(bool v) {
    if (_running == v) return;
    setState(() => _running = v);
    if (v) {
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    unawaited(_applyWakeLock());
  }

  void _tick() {
    if (!_running) return;
    if (_left.inSeconds <= 1) {
      if (_phase == _Phase.focus) {
        _onFocusComplete();
      } else {
        _onRestComplete();
      }
      return;
    }
    setState(() => _left -= const Duration(seconds: 1));
  }

  void _hapticBurst() {
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
    }
  }

  void _onFocusComplete() {
    _hapticBurst();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('专注完成，进入休息')),
      );
    }
    _ticker?.cancel();
    setState(() {
      _phase = _Phase.rest;
      _left = Duration(seconds: _restSeconds);
      _running = true;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_applyWakeLock());
  }

  void _onRestComplete() {
    _hapticBurst();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('休息结束，开始下一轮专注')),
      );
    }
    _ticker?.cancel();
    setState(() {
      _phase = _Phase.focus;
      _left = Duration(seconds: _sessionFocusSeconds);
      _running = true;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_applyWakeLock());
  }

  void _start() {
    if (!_sessionLocked) {
      setState(() => _sessionLocked = true);
    }
    _setRunning(true);
  }

  void _pause() {
    _setRunning(false);
  }

  Future<void> _terminate() async {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _sessionLocked = false;
      _phase = _Phase.focus;
      _left = Duration(seconds: _sessionFocusSeconds);
    });
    await WakelockPlus.disable();
    await _player.stop();
    if (mounted) context.pop();
  }

  String _mmss(Duration d) {
    final s = d.inSeconds.clamp(0, 24 * 3600);
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _pickBgm(String? asset) async {
    setState(() => _bgmAsset = asset);
    await _player.stop();
    if (asset == null) return;
    try {
      await _player.play(AssetSource(asset));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法播放：请确认 assets/audio/ 下存在对应 mp3')),
        );
      }
    }
  }

  Future<void> _editFocusDuration() async {
    if (_sessionLocked || _running) return;
    final c = TextEditingController(text: '${_sessionFocusSeconds ~/ 60}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本轮专注时长（分钟）'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '1–180'),
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('取消')),
          OutlinedButton(
            onPressed: () {
              final m = int.tryParse(c.text.trim()) ?? (_sessionFocusSeconds ~/ 60);
              final sec = (m.clamp(1, 180) * 60);
              setState(() {
                _sessionFocusSeconds = sec;
                if (_phase == _Phase.focus) {
                  _left = Duration(seconds: sec);
                }
              });
              ctx.pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phaseLabel = _phase == _Phase.focus ? '专注' : '休息';
    final phaseColor = _phase == _Phase.focus ? AppColors.primary : AppColors.success;
    final ring = math.min(MediaQuery.sizeOf(context).width - 40, 300.0);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.taskId != null)
                Text(
                  '任务 ${widget.taskId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              if (widget.taskId != null) const SizedBox(height: 6),
              Text(
                phaseLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: phaseColor,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: ring,
                      height: ring,
                      child: CustomPaint(
                        painter: _CountdownRingPainter(
                          progress: _progress.clamp(0.0, 1.0),
                          color: phaseColor,
                          trackColor: AppColors.outline.withValues(alpha: 0.55),
                          strokeWidth: 14,
                        ),
                        child: Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: (_sessionLocked || _running) ? null : _editFocusDuration,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _mmss(_left),
                                  style: TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                    color: AppColors.onSurface,
                                    decoration: (!_sessionLocked && !_running) ? TextDecoration.underline : null,
                                    decorationColor: AppColors.primary,
                                    decorationThickness: 2,
                                  ),
                                ),
                                if (!_sessionLocked && !_running) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '长按修改时长',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('无'),
                          selected: _bgmAsset == null,
                          onSelected: (v) {
                            if (!v) return;
                            _pickBgm(null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('雨声'),
                          selected: _bgmAsset == 'audio/rain.mp3',
                          onSelected: (v) {
                            if (!v) return;
                            _pickBgm('audio/rain.mp3');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('白噪'),
                          selected: _bgmAsset == 'audio/white_noise.mp3',
                          onSelected: (v) {
                            if (!v) return;
                            _pickBgm('audio/white_noise.mp3');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('咖啡'),
                          selected: _bgmAsset == 'audio/cafe.mp3',
                          onSelected: (v) {
                            if (!v) return;
                            _pickBgm('audio/cafe.mp3');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _running ? null : _start,
                    child: const Text('开始'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _running ? _pause : null,
                    child: const Text('暂停'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _terminate,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('终止'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - strokeWidth / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
