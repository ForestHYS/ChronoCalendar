import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/agent_client_context.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../data/providers.dart';

class AgentChatPage extends ConsumerStatefulWidget {
  const AgentChatPage({super.key});

  @override
  ConsumerState<AgentChatPage> createState() => _AgentChatPageState();
}

class _AgentChatPageState extends ConsumerState<AgentChatPage> {
  final _inputC = TextEditingController();
  final _scrollC = ScrollController();

  String? _sessionId;
  bool _sending = false;
  bool _loading = true;
  bool _listening = false;
  bool _voiceBusy = false;

  final List<_ChatItem> _items = [];

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  /// 启动时尝试恢复最近一次会话及其历史消息。
  Future<void> _restoreSession() async {
    try {
      final repo = ref.read(agentRepositoryProvider);
      final sessions = await repo.getSessions();
      if (sessions.isNotEmpty) {
        _sessionId = sessions.first['id'] as String?;
        if (_sessionId != null) {
          final msgs = await repo.getMessages(_sessionId!);
          final restored = <_ChatItem>[];
          for (final m in msgs) {
            final role = m['role'] as String?;
            if (role == 'user') {
              restored.add(_ChatItem.user(m['content_text'] as String? ?? ''));
            } else if (role == 'assistant') {
              final json = m['content_json'];
              if (json is Map<String, dynamic>) {
                // 历史中的 open_editor 草稿和 approval_required 审批均已操作过，标记为已提交
                final alreadyActed =
                    json['type'] == 'open_editor' ||
                    json['type'] == 'approval_required' ||
                    (json['type'] == 'plan_preview' &&
                        json['plan_confirmed'] == true) ||
                    (json['type'] == 'plan_questions' &&
                        json['plan_answered'] == true) ||
                    (json['type'] == 'plan_outline' &&
                        json['outline_confirmed'] == true);
                restored.add(
                  _ChatItem.assistant(
                    json,
                    messageId: m['id'] as String?,
                    initialSubmitted: alreadyActed,
                  ),
                );
              } else {
                restored.add(
                  _ChatItem.assistant({
                    'type': 'message',
                    'text': m['content_text'] ?? '',
                  }),
                );
              }
            }
          }
          if (mounted) {
            setState(() => _items.addAll(restored));
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
          }
        }
      }
    } catch (_) {
      // 恢复失败不影响正常使用，静默忽略
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ref.read(speechRecognizerServiceProvider).cancel();
    ref.read(speechSynthesizerServiceProvider).stop();
    _inputC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _ensureSession() async {
    if (_sessionId != null) return;
    final id = await ref.read(agentRepositoryProvider).createSession();
    _sessionId = id;
  }

  Future<void> _toggleListening() async {
    if (_voiceBusy || _sending) return;
    final recognizer = ref.read(speechRecognizerServiceProvider);
    if (_listening) {
      setState(() => _voiceBusy = true);
      try {
        await recognizer.stop();
      } finally {
        if (mounted) {
          setState(() {
            _listening = false;
            _voiceBusy = false;
          });
        }
      }
      return;
    }

    setState(() => _voiceBusy = true);
    try {
      final started = await recognizer.listen(
        localeId: 'zh_CN',
        onResult: (text, _) {
          if (!mounted) return;
          setState(() {
            _inputC.text = text;
            _inputC.selection = TextSelection.collapsed(offset: text.length);
          });
        },
        onDone: () {
          if (mounted) setState(() => _listening = false);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
          unawaited(showAppErrorDialog(context, title: '语音识别失败', error: error));
        },
      );
      if (!mounted) return;
      setState(() {
        _listening = started;
        _voiceBusy = false;
      });
      if (!started) {
        await showAppErrorDialog(
          context,
          title: '语音识别不可用',
          error: StateError('当前设备没有可用的系统语音识别服务'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceBusy = false;
      });
      await showAppErrorDialog(context, title: '语音识别失败', error: e);
    }
  }

  Future<void> _speakText(String text) async {
    try {
      await ref.read(speechSynthesizerServiceProvider).speak(text);
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '语音播放失败', error: e);
      }
    }
  }

  Future<void> _speakAssistantPayload(Map<String, dynamic> payload) async {
    final text = _speakableText(payload);
    if (text == null || text.trim().isEmpty) return;
    await _speakText(text);
  }

  String? _speakableText(Map<String, dynamic> payload) {
    final type = payload['type'];
    if (type == 'message' || type == 'query_result') {
      return payload['text'] as String?;
    }
    if (type == 'open_editor') {
      final message = payload['message'] as String?;
      final draft = payload['task_draft'];
      if (message != null && message.trim().isNotEmpty) return message;
      if (draft is Map<String, dynamic>) {
        final title = draft['title'] as String?;
        if (title != null && title.trim().isNotEmpty) {
          return '已为你生成任务草稿：$title';
        }
      }
      return '已为你生成任务草稿';
    }
    if (type == 'approval_required') {
      return payload['summary'] as String? ?? '这个操作需要你的确认';
    }
    if (type == 'plan_questions' ||
        type == 'plan_outline' ||
        type == 'plan_preview') {
      return payload['message'] as String?;
    }
    return payload['text'] as String?;
  }

  Future<void> _sendInteraction({
    required String userLabel,
    required Map<String, dynamic> interaction,
  }) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _items.add(_ChatItem.user(userLabel));
    });
    try {
      await _ensureSession();
      final sent = await ref
          .read(agentRepositoryProvider)
          .sendMessage(
            sessionId: _sessionId!,
            text: userLabel,
            clientContext: buildAgentClientContext(),
            interaction: interaction,
          );
      final resp = sent['response'] as Map<String, dynamic>? ?? {};
      setState(() {
        _items.add(
          _ChatItem.assistant(
            resp,
            messageId: sent['assistant_message_id'] as String?,
          ),
        );
      });
      if (resp['refresh_tasks'] == true) {
        ref.read(taskRepositoryProvider).refreshTasks();
      }
      _scrollToBottom();
      if (ref.read(appSettingsRepositoryProvider).agentAutoSpeak) {
        await _speakAssistantPayload(resp);
      }
    } catch (e) {
      if (mounted) await showAppErrorDialog(context, title: '发送失败', error: e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _markAssistantPayload(String messageId, Map<String, dynamic> patch) {
    setState(() {
      final idx = _items.indexWhere(
        (it) => !it.isUser && it.messageId == messageId,
      );
      if (idx < 0) return;
      final p = _items[idx].payload;
      if (p == null) return;
      _items[idx] = _ChatItem.assistant(
        {...p, ...patch},
        messageId: messageId,
        initialSubmitted: true,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputC.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _items.add(_ChatItem.user(text));
      _inputC.clear();
    });
    try {
      await _ensureSession();
      final sent = await ref
          .read(agentRepositoryProvider)
          .sendMessage(
            sessionId: _sessionId!,
            text: text,
            clientContext: buildAgentClientContext(),
          );
      final resp = sent['response'] as Map<String, dynamic>? ?? {};
      setState(() {
        _items.add(
          _ChatItem.assistant(
            resp,
            messageId: sent['assistant_message_id'] as String?,
          ),
        );
      });
      // 后端标记了任务已直接创建（create_immediately=true），立即刷新本地任务缓存
      if (resp['refresh_tasks'] == true) {
        ref.read(taskRepositoryProvider).refreshTasks();
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) await showAppErrorDialog(context, title: '发送失败', error: e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollC.hasClients) return;
      _scrollC.animateTo(
        _scrollC.position.maxScrollExtent + 220,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _startNewSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启新对话'),
        content: const Text('是否开启新的对话界面？注意：该界面的历史信息将不会保留'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 创建新会话
    try {
      final id = await ref.read(agentRepositoryProvider).createSession();
      setState(() {
        _sessionId = id;
        _items.clear();
      });
    } catch (e) {
      if (mounted) await showAppErrorDialog(context, title: '创建失败', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(appSettingsRepositoryProvider);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('AI 助手'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              appSettings.agentAutoSpeak
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
            ),
            tooltip: appSettings.agentAutoSpeak ? '关闭自动朗读' : '开启自动朗读',
            onPressed: () => ref
                .read(appSettingsRepositoryProvider)
                .setAgentAutoSpeak(!appSettings.agentAutoSpeak),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新对话',
            onPressed: _startNewSession,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            const LinearProgressIndicator()
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '你好！我可以帮你创建任务、查询日程或回答问题。',
                style: TextStyle(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollC,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final it = _items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: it.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: it.isUser
                        ? _UserBubble(text: it.text!)
                        : _AssistantCard(
                            payload: it.payload!,
                            messageId: it.messageId,
                            initialSubmitted: it.initialSubmitted,
                            onOpenEditor: _openEditorFromDraft,
                            onFollowUp: _appendAssistantPayload,
                            onSpeak: _speakText,
                            onPlanConfirmed: (messageId) {
                              _markAssistantPayload(messageId, {
                                'plan_confirmed': true,
                              });
                            },
                            onPlanInteractionDone: _markAssistantPayload,
                            onSendInteraction: _sendInteraction,
                          ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputC,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '输入：创建任务 / 查询明天任务 ...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton.filledTonal(
                      tooltip: _listening ? '停止语音输入' : '语音输入',
                      onPressed: (_sending || _voiceBusy)
                          ? null
                          : _toggleListening,
                      icon: _voiceBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _listening
                                  ? Icons.stop_circle_outlined
                                  : Icons.mic_none_outlined,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditorFromDraft(Map<String, dynamic> draft) {
    context.push('/task/new', extra: {'agent_draft': draft});
  }

  void _appendAssistantPayload(Map<String, dynamic> payload) {
    setState(() {
      _items.add(_ChatItem.assistant(payload));
    });
    _scrollToBottom();
    if (ref.read(appSettingsRepositoryProvider).agentAutoSpeak) {
      unawaited(_speakAssistantPayload(payload));
    }
  }
}

class _ChatItem {
  _ChatItem._({
    required this.isUser,
    this.text,
    this.payload,
    this.messageId,
    this.initialSubmitted = false,
  });
  final bool isUser;
  final String? text;
  final Map<String, dynamic>? payload;
  final String? messageId;
  final bool initialSubmitted;

  factory _ChatItem.user(String t) => _ChatItem._(isUser: true, text: t);
  factory _ChatItem.assistant(
    Map<String, dynamic> payload, {
    String? messageId,
    bool initialSubmitted = false,
  }) => _ChatItem._(
    isUser: false,
    payload: payload,
    messageId: messageId,
    initialSubmitted: initialSubmitted,
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(text, style: const TextStyle(color: AppColors.onSurface)),
        ),
      ),
    );
  }
}

class _AssistantCard extends ConsumerStatefulWidget {
  const _AssistantCard({
    required this.payload,
    required this.onOpenEditor,
    required this.onFollowUp,
    required this.onSendInteraction,
    required this.onSpeak,
    this.messageId,
    this.initialSubmitted = false,
    this.onPlanConfirmed,
    this.onPlanInteractionDone,
  });
  final Map<String, dynamic> payload;
  final String? messageId;
  final void Function(Map<String, dynamic> draft) onOpenEditor;
  final void Function(Map<String, dynamic> payload) onFollowUp;
  final Future<void> Function(String text) onSpeak;
  final Future<void> Function({
    required String userLabel,
    required Map<String, dynamic> interaction,
  })
  onSendInteraction;
  final void Function(String messageId)? onPlanConfirmed;
  final void Function(String messageId, Map<String, dynamic> patch)?
  onPlanInteractionDone;
  final bool initialSubmitted;

  @override
  ConsumerState<_AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends ConsumerState<_AssistantCard> {
  late bool _submitted;

  @override
  void initState() {
    super.initState();
    _submitted = widget.initialSubmitted;
  }

  void _handleOpenEditor(Map<String, dynamic> draft) {
    setState(() => _submitted = true);
    widget.onOpenEditor(draft);
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final onFollowUp = widget.onFollowUp;
    final type = payload['type'];
    if (type == 'open_editor') {
      final draft = (payload['task_draft'] is Map<String, dynamic>)
          ? (payload['task_draft'] as Map<String, dynamic>)
          : <String, dynamic>{};
      final conflict = payload['conflict'];
      final message = payload['message'];

      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '任务草稿',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _draftSummary(draft),
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
                if (message is String && message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(message),
                ],
                if (conflict is Map<String, dynamic> && !_submitted) ...[
                  const SizedBox(height: 10),
                  _ConflictBlock(
                    conflict: conflict,
                    baseDraft: draft,
                    onOpenEditor: _handleOpenEditor,
                  ),
                ],
                const SizedBox(height: 12),
                if (_submitted)
                  Row(
                    children: const [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.onSurfaceVariant,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '已发送至编辑页',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  )
                else
                  FilledButton(
                    onPressed: () => _handleOpenEditor(draft),
                    child: const Text('打开编辑页'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (type == 'message') {
      final text = payload['text'] as String? ?? '我暂时没理解你的意思。';
      final items = payload['items'];
      if (items is List && items.isNotEmpty) {
        return _AgentTaskListCard(
          text: text,
          items: items,
          onSpeak: widget.onSpeak,
        );
      }
      return _assistantTextCard(text);
    }

    if (type == 'query') {
      final q = payload['query'];
      return _assistantTextCard('查询请求：${q ?? ''}');
    }

    if (type == 'approval_required') {
      final summary = payload['summary'] as String? ?? '需要你的确认';
      final approvalId = payload['approval_id'] as String?;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          color: AppColors.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '需要授权',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(summary),
                const SizedBox(height: 12),
                if (_submitted)
                  Row(
                    children: const [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.onSurfaceVariant,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '已处理',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: approvalId == null
                              ? null
                              : () async {
                                  try {
                                    final r = await ref
                                        .read(agentRepositoryProvider)
                                        .rejectApproval(approvalId);
                                    setState(() => _submitted = true);
                                    onFollowUp(r);
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showAppErrorDialog(
                                        context,
                                        title: '操作失败',
                                        error: e,
                                      );
                                    }
                                  }
                                },
                          child: const Text('拒绝'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: approvalId == null
                              ? null
                              : () async {
                                  try {
                                    final r = await ref
                                        .read(agentRepositoryProvider)
                                        .approveApproval(approvalId);
                                    // 批准后同步本地任务缓存，使主页立即反映变更
                                    await ref
                                        .read(taskRepositoryProvider)
                                        .refreshTasks();
                                    setState(() => _submitted = true);
                                    onFollowUp(r);
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showAppErrorDialog(
                                        context,
                                        title: '操作失败',
                                        error: e,
                                      );
                                    }
                                  }
                                },
                          child: const Text('批准'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (type == 'query_result') {
      final text = payload['text'] as String? ?? '查询结果如下：';
      final items = payload['items'];
      return _AgentTaskListCard(
        text: text,
        items: items,
        onSpeak: widget.onSpeak,
      );
    }

    if (type == 'plan_questions') {
      return _PlanQuestionsCard(
        payload: payload,
        messageId: widget.messageId,
        initialSubmitted:
            _submitted ||
            widget.initialSubmitted ||
            payload['plan_answered'] == true,
        onSendInteraction: widget.onSendInteraction,
        onFollowUp: onFollowUp,
        onDone: widget.onPlanInteractionDone,
      );
    }

    if (type == 'plan_outline') {
      return _PlanOutlineCard(
        payload: payload,
        messageId: widget.messageId,
        initialSubmitted:
            _submitted ||
            widget.initialSubmitted ||
            payload['outline_confirmed'] == true,
        onSendInteraction: widget.onSendInteraction,
        onFollowUp: onFollowUp,
        onDone: widget.onPlanInteractionDone,
      );
    }

    if (type == 'plan_preview') {
      return _PlanPreviewCard(
        payload: payload,
        messageId: widget.messageId,
        initialSubmitted:
            _submitted ||
            widget.initialSubmitted ||
            payload['plan_confirmed'] == true,
        onFollowUp: onFollowUp,
        onPlanConfirmed: widget.onPlanConfirmed,
      );
    }

    return _assistantTextCard('收到。');
  }

  Widget _assistantTextCard(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(text)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '朗读',
                visualDensity: VisualDensity.compact,
                onPressed: text.trim().isEmpty
                    ? null
                    : () => widget.onSpeak(text),
                icon: const Icon(Icons.volume_up_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _draftSummary(Map<String, dynamic> d) {
    final title = (d['title'] as String?)?.trim() ?? '（未命名）';
    final type = (d['type'] as String?)?.trim();
    final typeLabel = switch (type) {
      'block' => '固定时段',
      'ddl' => '截止日期',
      'todo' => '待办',
      _ => type ?? '',
    };
    final startAt = (d['start_at'] as String?)?.trim();
    final endAt = (d['end_at'] as String?)?.trim();
    final dueAt = (d['due_at'] as String?)?.trim();
    final em = d['expected_minutes'];
    final subs = d['subtasks'];
    final subCount = subs is List ? subs.length : 0;
    final buf = StringBuffer();
    if (typeLabel.isNotEmpty) buf.write('$typeLabel · ');
    buf.write(title);
    if (type == 'block' && startAt != null && endAt != null) {
      buf.write(' · $startAt - $endAt');
    } else if (dueAt != null && dueAt.isNotEmpty) {
      buf.write(' · 截止 $dueAt');
    }
    if (type == 'todo' && em != null) buf.write(' · 预计 $em 分钟');
    if (type == 'todo' && subCount > 0) buf.write(' · $subCount 个子任务');
    return buf.toString();
  }
}

/// 任务查询结果：上方文字简述 + 下方每条带「查看详情」。
class _AgentTaskListCard extends ConsumerWidget {
  const _AgentTaskListCard({
    required this.text,
    required this.items,
    required this.onSpeak,
  });

  final String text;
  final dynamic items;
  final Future<void> Function(String text) onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(text)),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '朗读',
                    visualDensity: VisualDensity.compact,
                    onPressed: text.trim().isEmpty ? null : () => onSpeak(text),
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (list.isNotEmpty) ...[
                ...list.take(12).map((e) => _AgentTaskListRow(item: e)),
                if (list.length > 12)
                  Text(
                    '… 另有 ${list.length - 12} 个任务未列出',
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentTaskListRow extends ConsumerWidget {
  const _AgentTaskListRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = (item['id'] as String?)?.trim();
    final title = item['title'] as String? ?? '';
    final t = item['type'] as String? ?? '';
    final timeSummary = (item['time_summary'] as String?)?.trim();
    final startAt = item['start_at'] as String?;
    final endAt = item['end_at'] as String?;
    final dueAt = item['due_at'] as String?;
    final subtitle = timeSummary?.isNotEmpty == true
        ? timeSummary!
        : ((t == 'block' && startAt != null && endAt != null)
              ? '$startAt - $endAt'
              : (dueAt ?? ''));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (id != null && id.isNotEmpty)
            TextButton(
              onPressed: () {
                context.push('/task/$id');
                ref.read(taskRepositoryProvider).touchTaskAfterNavigation(id);
              },
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('查看详情'),
            ),
        ],
      ),
    );
  }
}

String _planTaskTypeLabel(String? type) {
  switch (type) {
    case 'block':
      return '固定时段';
    case 'ddl':
      return '截止';
    case 'todo':
      return '待办';
    default:
      return type ?? '';
  }
}

String? _planTaskTimeLabel(Map<String, dynamic> task) {
  final typ = task['type'] as String?;
  if (typ == 'block') {
    final s = task['start_at'] as String?;
    final e = task['end_at'] as String?;
    if (s != null && e != null) {
      final ss = s.length >= 16 ? s.substring(0, 16).replaceAll('T', ' ') : s;
      final ee = e.length >= 16 ? e.substring(11, 16) : e;
      return '$ss — $ee';
    }
  }
  final due = task['due_at'] as String?;
  if (due != null && due.length >= 10) {
    return due.substring(0, 10);
  }
  return null;
}

class _PlanQuestionsCard extends StatefulWidget {
  const _PlanQuestionsCard({
    required this.payload,
    required this.onSendInteraction,
    this.messageId,
    this.initialSubmitted = false,
    this.onFollowUp,
    this.onDone,
  });

  final Map<String, dynamic> payload;
  final String? messageId;
  final bool initialSubmitted;
  final Future<void> Function({
    required String userLabel,
    required Map<String, dynamic> interaction,
  })
  onSendInteraction;
  final void Function(Map<String, dynamic> payload)? onFollowUp;
  final void Function(String messageId, Map<String, dynamic> patch)? onDone;

  @override
  State<_PlanQuestionsCard> createState() => _PlanQuestionsCardState();
}

class _PlanQuestionsCardState extends State<_PlanQuestionsCard> {
  late final List<Map<String, dynamic>> _questions;
  final Map<String, dynamic> _answers = {};
  late bool _submitted;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final qs = widget.payload['questions'];
    _questions = (qs is List)
        ? qs.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    _submitted =
        widget.initialSubmitted || widget.payload['plan_answered'] == true;
  }

  bool get _allAnswered {
    for (final q in _questions) {
      final id = q['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final v = _answers[id];
      if (v == null) return false;
      if (v is List && v.isEmpty) return false;
      if (v is String && v.isEmpty) return false;
    }
    return _questions.isNotEmpty;
  }

  void _pickOption(Map<String, dynamic> q, String optionId) {
    if (_submitted) return;
    final id = q['id'] as String? ?? '';
    final multi = q['multi'] == true;
    setState(() {
      if (multi) {
        final cur = (_answers[id] is List)
            ? List<String>.from(_answers[id] as List)
            : <String>[];
        if (cur.contains(optionId)) {
          cur.remove(optionId);
        } else {
          cur.add(optionId);
        }
        _answers[id] = cur;
      } else {
        _answers[id] = optionId;
      }
    });
  }

  bool _isSelected(Map<String, dynamic> q, String optionId) {
    final id = q['id'] as String? ?? '';
    final v = _answers[id];
    if (q['multi'] == true) {
      return v is List && v.contains(optionId);
    }
    return v == optionId;
  }

  Future<void> _submit() async {
    if (_submitted || _submitting || !_allAnswered) return;
    setState(() => _submitting = true);
    try {
      final planContext = widget.payload['plan_context'];
      await widget.onSendInteraction(
        userLabel: '已提交规划选项',
        interaction: {
          'type': 'plan_answers',
          'source_message_id': widget.messageId,
          'answers': Map<String, dynamic>.from(_answers),
          if (planContext is Map<String, dynamic>) 'plan_context': planContext,
        },
      );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      final mid = widget.messageId;
      if (mid != null && mid.isNotEmpty) {
        widget.onDone?.call(mid, {'plan_answered': true});
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.payload['message'] as String? ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '细化规划需求',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              ..._questions.map((q) {
                final qText = q['text'] as String? ?? '';
                final options = q['options'];
                final opts = (options is List)
                    ? options.whereType<Map<String, dynamic>>().toList()
                    : <Map<String, dynamic>>[];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        qText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: opts.map((o) {
                          final oid = o['id'] as String? ?? '';
                          final label = o['label'] as String? ?? oid;
                          final selected = _isSelected(q, oid);
                          return FilterChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: _submitted
                                ? null
                                : (_) => _pickOption(q, oid),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
              if (_submitted)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '已提交选项',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: !_allAnswered || _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认提交'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanOutlineCard extends StatefulWidget {
  const _PlanOutlineCard({
    required this.payload,
    required this.onSendInteraction,
    this.messageId,
    this.initialSubmitted = false,
    this.onFollowUp,
    this.onDone,
  });

  final Map<String, dynamic> payload;
  final String? messageId;
  final bool initialSubmitted;
  final Future<void> Function({
    required String userLabel,
    required Map<String, dynamic> interaction,
  })
  onSendInteraction;
  final void Function(Map<String, dynamic> payload)? onFollowUp;
  final void Function(String messageId, Map<String, dynamic> patch)? onDone;

  @override
  State<_PlanOutlineCard> createState() => _PlanOutlineCardState();
}

class _PlanOutlineCardState extends State<_PlanOutlineCard> {
  late bool _submitted;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _submitted =
        widget.initialSubmitted || widget.payload['outline_confirmed'] == true;
  }

  Future<void> _confirm() async {
    if (_submitted || _submitting) return;
    setState(() => _submitting = true);
    try {
      final planContext = widget.payload['plan_context'];
      await widget.onSendInteraction(
        userLabel: '确认方案，生成日程',
        interaction: {
          'type': 'confirm_outline',
          'source_message_id': widget.messageId,
          if (planContext is Map<String, dynamic>) 'plan_context': planContext,
        },
      );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      final mid = widget.messageId;
      if (mid != null && mid.isNotEmpty) {
        widget.onDone?.call(mid, {'outline_confirmed': true});
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planTitle = widget.payload['plan_title'] as String? ?? '长期规划';
    final message = widget.payload['message'] as String? ?? '';
    final outlineText = widget.payload['outline_text'] as String? ?? '';
    final phases = widget.payload['phases'];
    final phaseList = (phases is List)
        ? phases.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final summary = widget.payload['planned_schedule_summary'];
    final summaryMap = summary is Map<String, dynamic>
        ? summary
        : <String, dynamic>{};
    final todoN = summaryMap['todo_count'];
    final blockN = summaryMap['block_count'];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                planTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ],
              if (outlineText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(outlineText),
              ],
              if (todoN != null || blockN != null) ...[
                const SizedBox(height: 8),
                Text(
                  '预计排程：约 ${todoN ?? 0} 个待办、${blockN ?? 0} 个固定时段',
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (phaseList.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  '阶段安排',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...phaseList.map((p) {
                  final title = p['title'] as String? ?? '';
                  final desc = p['description'] as String? ?? '';
                  final hint = p['duration_hint'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hint.isNotEmpty ? '$title（$hint）' : title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (desc.isNotEmpty)
                          Text(
                            desc,
                            style: const TextStyle(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              if (_submitted)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '已确认方案',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: _submitting ? null : _confirm,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认方案，生成日程'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanPreviewCard extends ConsumerStatefulWidget {
  const _PlanPreviewCard({
    required this.payload,
    required this.onFollowUp,
    this.messageId,
    this.initialSubmitted = false,
    this.onPlanConfirmed,
  });

  final Map<String, dynamic> payload;
  final String? messageId;
  final bool initialSubmitted;
  final void Function(Map<String, dynamic> payload) onFollowUp;
  final void Function(String messageId)? onPlanConfirmed;

  @override
  ConsumerState<_PlanPreviewCard> createState() => _PlanPreviewCardState();
}

class _PlanPreviewCardState extends ConsumerState<_PlanPreviewCard> {
  late final List<Map<String, dynamic>> _taskList;
  late Set<int> _selected;
  late bool _submitted;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final tasks = widget.payload['tasks'];
    _taskList = (tasks is List)
        ? tasks.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    _selected = Set<int>.from(List.generate(_taskList.length, (i) => i));
    _submitted =
        widget.initialSubmitted || widget.payload['plan_confirmed'] == true;
  }

  void _selectAll() {
    setState(() {
      _selected = Set<int>.from(List.generate(_taskList.length, (i) => i));
    });
  }

  void _selectNone() {
    setState(() => _selected.clear());
  }

  void _toggle(int index) {
    if (_submitted) return;
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  Future<void> _confirmSelected() async {
    if (_submitted || _creating || _selected.isEmpty) return;
    final selectedTasks = _selected.map((i) => _taskList[i]).toList();
    setState(() => _creating = true);
    try {
      final r = await ref
          .read(agentRepositoryProvider)
          .confirmPlan(
            selectedTasks,
            clientContext: buildAgentClientContext(),
            sourceMessageId: widget.messageId,
          );
      await ref.read(taskRepositoryProvider).refreshTasks();
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _creating = false;
      });
      final mid = widget.messageId;
      if (mid != null && mid.isNotEmpty) {
        widget.onPlanConfirmed?.call(mid);
      }
      widget.onFollowUp(r);
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        await showAppErrorDialog(context, title: '创建失败', error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final planTitle = widget.payload['plan_title'] as String? ?? '长期规划';
    final message = widget.payload['message'] as String? ?? '';
    final selectedCount = _selected.length;
    final total = _taskList.length;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                planTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ],
              if (_taskList.isNotEmpty && !_submitted) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '已选 $selectedCount / $total',
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _selectAll,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: _selectNone,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('全不选'),
                    ),
                  ],
                ),
              ],
              if (_taskList.isNotEmpty) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _taskList.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final t = _taskList[index];
                      final title = t['title'] as String? ?? '';
                      final typ = t['type'] as String?;
                      final typeLabel = _planTaskTypeLabel(typ);
                      final subtasks = t['subtasks'];
                      final subtaskCount = (subtasks is List)
                          ? subtasks.length
                          : 0;
                      final timeLabel = _planTaskTimeLabel(t);
                      final checked = _selected.contains(index);
                      final meta = [
                        if (typeLabel.isNotEmpty) typeLabel,
                        if (timeLabel != null && timeLabel.isNotEmpty)
                          timeLabel,
                        if (subtaskCount > 0) '$subtaskCount 个子任务',
                      ].join(' · ');
                      return InkWell(
                        onTap: _submitted ? null : () => _toggle(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: checked,
                                  onChanged: _submitted
                                      ? null
                                      : (_) => _toggle(index),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (meta.isNotEmpty)
                                      Text(
                                        meta,
                                        style: const TextStyle(
                                          color: AppColors.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_submitted)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '已创建到日程',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed:
                      _taskList.isEmpty || selectedCount == 0 || _creating
                      ? null
                      : _confirmSelected,
                  child: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          selectedCount == total
                              ? '创建全部 ($total)'
                              : '创建所选 ($selectedCount)',
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictBlock extends StatelessWidget {
  const _ConflictBlock({
    required this.conflict,
    required this.baseDraft,
    required this.onOpenEditor,
  });

  final Map<String, dynamic> conflict;
  final Map<String, dynamic> baseDraft;
  final void Function(Map<String, dynamic> draft) onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final overlaps = conflict['overlaps'];
    final suggestions = conflict['suggestions'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('检测到时间冲突', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (overlaps is List && overlaps.isNotEmpty)
          ...overlaps.take(2).map((e) {
            if (e is! Map<String, dynamic>) return const SizedBox.shrink();
            final t = e['title'] as String? ?? '';
            final s = e['start_at'] as String? ?? '';
            final en = e['end_at'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $t（$s - $en）',
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
            );
          }),
        if (suggestions is List && suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((s) {
              if (s is! Map<String, dynamic>) return const SizedBox.shrink();
              final label = s['label'] as String? ?? '建议时间';
              return OutlinedButton(
                onPressed: () {
                  final next = Map<String, dynamic>.from(baseDraft);
                  next['start_at'] = s['start_at'];
                  next['end_at'] = s['end_at'];
                  onOpenEditor(next);
                },
                child: Text(label),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
