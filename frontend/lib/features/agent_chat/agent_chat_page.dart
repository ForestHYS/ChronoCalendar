import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                    json['type'] == 'approval_required';
                restored.add(
                  _ChatItem.assistant(json, initialSubmitted: alreadyActed),
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
    _inputC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _ensureSession() async {
    if (_sessionId != null) return;
    final id = await ref.read(agentRepositoryProvider).createSession();
    _sessionId = id;
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
      final resp = await ref
          .read(agentRepositoryProvider)
          .sendMessage(sessionId: _sessionId!, text: text);
      setState(() {
        _items.add(_ChatItem.assistant(resp));
      });
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
                            initialSubmitted: it.initialSubmitted,
                            onOpenEditor: _openEditorFromDraft,
                            onFollowUp: _appendAssistantPayload,
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
  }
}

class _ChatItem {
  _ChatItem._({
    required this.isUser,
    this.text,
    this.payload,
    this.initialSubmitted = false,
  });
  final bool isUser;
  final String? text;
  final Map<String, dynamic>? payload;
  final bool initialSubmitted;

  factory _ChatItem.user(String t) => _ChatItem._(isUser: true, text: t);
  factory _ChatItem.assistant(
    Map<String, dynamic> payload, {
    bool initialSubmitted = false,
  }) => _ChatItem._(
    isUser: false,
    payload: payload,
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
    super.key,
    required this.payload,
    required this.onOpenEditor,
    required this.onFollowUp,
    this.initialSubmitted = false,
  });
  final Map<String, dynamic> payload;
  final void Function(Map<String, dynamic> draft) onOpenEditor;
  final void Function(Map<String, dynamic> payload) onFollowUp;
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
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text),
                const SizedBox(height: 10),
                if (items is List && items.isNotEmpty)
                  ...items.take(8).map((e) {
                    if (e is! Map<String, dynamic>)
                      return const SizedBox.shrink();
                    final title = e['title'] as String? ?? '';
                    final t = e['type'] as String? ?? '';
                    final startAt = e['start_at'] as String?;
                    final endAt = e['end_at'] as String?;
                    final dueAt = e['due_at'] as String?;
                    final subtitle =
                        (t == 'block' && startAt != null && endAt != null)
                        ? '$startAt - $endAt'
                        : (dueAt ?? '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                              ),
                            ),
                        ],
                      ),
                    );
                  })
                else
                  const Text(
                    '未找到匹配任务',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return _assistantTextCard('收到。');
  }

  Widget _assistantTextCard(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Card(
        child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
      ),
    );
  }

  String _draftSummary(Map<String, dynamic> d) {
    final title = (d['title'] as String?)?.trim();
    final type = (d['type'] as String?)?.trim();
    final startAt = (d['start_at'] as String?)?.trim();
    final endAt = (d['end_at'] as String?)?.trim();
    if (type == 'block' && startAt != null && endAt != null) {
      return '${title ?? '（未命名）'} · $startAt - $endAt';
    }
    return title ?? '（未命名）';
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
