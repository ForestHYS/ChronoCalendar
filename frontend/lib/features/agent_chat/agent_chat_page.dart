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

  final List<_ChatItem> _items = [];

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
      final resp = await ref.read(agentRepositoryProvider).sendMessage(
            sessionId: _sessionId!,
            text: text,
          );
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
      ),
      body: Column(
        children: [
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
                    alignment: it.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: it.isUser
                        ? _UserBubble(text: it.text!)
                        : _AssistantCard(
                            payload: it.payload!,
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
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
  _ChatItem._({required this.isUser, this.text, this.payload});
  final bool isUser;
  final String? text;
  final Map<String, dynamic>? payload;

  factory _ChatItem.user(String t) => _ChatItem._(isUser: true, text: t);
  factory _ChatItem.assistant(Map<String, dynamic> payload) => _ChatItem._(isUser: false, payload: payload);
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

class _AssistantCard extends ConsumerWidget {
  const _AssistantCard({
    required this.payload,
    required this.onOpenEditor,
    required this.onFollowUp,
  });
  final Map<String, dynamic> payload;
  final void Function(Map<String, dynamic> draft) onOpenEditor;
  final void Function(Map<String, dynamic> payload) onFollowUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const Text('任务草稿', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_draftSummary(draft), style: const TextStyle(color: AppColors.onSurfaceVariant)),
                if (message is String && message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(message),
                ],
                if (conflict is Map<String, dynamic>) ...[
                  const SizedBox(height: 10),
                  _ConflictBlock(conflict: conflict, baseDraft: draft, onOpenEditor: onOpenEditor),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => onOpenEditor(draft),
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
                const Text('需要授权', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(summary),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: approvalId == null
                            ? null
                            : () async {
                                try {
                                  final r = await ref.read(agentRepositoryProvider).rejectApproval(approvalId);
                                  onFollowUp(r);
                                } catch (e) {
                                  if (context.mounted) {
                                    await showAppErrorDialog(context, title: '操作失败', error: e);
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
                                  final r = await ref.read(agentRepositoryProvider).approveApproval(approvalId);
                                  onFollowUp(r);
                                } catch (e) {
                                  if (context.mounted) {
                                    await showAppErrorDialog(context, title: '操作失败', error: e);
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
                    if (e is! Map<String, dynamic>) return const SizedBox.shrink();
                    final title = e['title'] as String? ?? '';
                    final t = e['type'] as String? ?? '';
                    final startAt = e['start_at'] as String?;
                    final endAt = e['end_at'] as String?;
                    final dueAt = e['due_at'] as String?;
                    final subtitle = (t == 'block' && startAt != null && endAt != null)
                        ? '$startAt - $endAt'
                        : (dueAt ?? '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (subtitle.isNotEmpty)
                            Text(subtitle, style: const TextStyle(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    );
                  })
                else
                  const Text('未找到匹配任务', style: TextStyle(color: AppColors.onSurfaceVariant)),
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(text),
        ),
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
  const _ConflictBlock({required this.conflict, required this.baseDraft, required this.onOpenEditor});

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
              child: Text('· $t（$s - $en）', style: const TextStyle(color: AppColors.onSurfaceVariant)),
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

