import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/scan_result.dart';
import '../models/scan_session.dart';
import '../providers/clamav_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        final sessions = av.sessions.reversed.toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          children: [
            _HistoryHeader(
              sessionCount: sessions.length,
              threatCount: sessions.fold<int>(
                0,
                (total, session) => total + session.threatsFound,
              ),
              onClear: sessions.isEmpty
                  ? null
                  : () => _confirmClear(context, av),
            ),
            const SizedBox(height: 20),
            if (sessions.isEmpty)
              const _EmptyHistory()
            else
              for (final session in sessions) ...[
                _SessionCard(session: session),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    ClamAvProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空历史记录？'),
        content: const Text('这会删除本机保存的扫描会话历史，不会影响隔离区或扫描结果文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await provider.clearHistory();
  }
}

class _HistoryHeader extends StatelessWidget {
  final int sessionCount;
  final int threatCount;
  final VoidCallback? onClear;

  const _HistoryHeader({
    required this.sessionCount,
    required this.threatCount,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.onPrimaryContainer.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.history_outlined,
              size: 38,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '扫描历史',
                  style: tt.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$sessionCount 次会话 · 累计 $threatCount 个威胁',
                  style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('清空历史'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.manage_search_outlined,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有扫描记录',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '完成一次文件扫描或系统级检查后，会话会自动保存到这里。',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ScanSession session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasThreats = session.threatsFound > 0;
    final statusColor = session.cancelled
        ? cs.onSurfaceVariant
        : (hasThreats ? cs.error : cs.tertiary);

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_statusIcon(session), color: statusColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _formatTarget(session.target),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            _EngineBadge(engine: session.engine),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(_formatDateTime(session.startedAt)),
              Text('${session.filesScanned} 个文件'),
              Text('${session.threatsFound} 个威胁'),
              Text(_formatDuration(session.duration)),
              if (session.cancelled) const Text('已取消'),
            ],
          ),
        ),
        children: [
          _SessionActions(session: session),
          const SizedBox(height: 10),
          if (session.results.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasThreats ? '本次扫描没有保存详细威胁条目' : '未发现威胁',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final result in session.results) _ThreatRow(result: result),
        ],
      ),
    );
  }

  IconData _statusIcon(ScanSession session) {
    if (session.cancelled) return Icons.pause_circle_outline;
    if (session.threatsFound > 0) return Icons.warning_amber_outlined;
    return Icons.verified_outlined;
  }
}

class _SessionActions extends StatelessWidget {
  final ScanSession session;

  const _SessionActions({required this.session});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                _copyText(context, _formatSessionResults(session), '扫描结果已复制'),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('复制结果'),
          ),
          OutlinedButton.icon(
            onPressed: session.logs.isEmpty
                ? null
                : () => _copyText(
                    context,
                    _formatSessionLogs(session),
                    '扫描日志已复制',
                  ),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('复制日志'),
          ),
          OutlinedButton.icon(
            onPressed: session.logs.isEmpty
                ? null
                : () => _showRawLogDialog(
                    context,
                    title: '${_engineName(session.engine)} Raw 日志',
                    text: _formatSessionLogs(session),
                  ),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Raw 日志'),
          ),
        ],
      ),
    );
  }
}

class _ThreatRow extends StatelessWidget {
  final ScanResult result;

  const _ThreatRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bug_report_outlined, size: 20, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.threatName,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  result.filePath,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                if (result.details != null && result.details!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    result.details!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(result.actionText, style: tt.labelSmall),
        ],
      ),
    );
  }
}

class _EngineBadge extends StatelessWidget {
  final String engine;

  const _EngineBadge({required this.engine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _engineName(engine),
        style: tt.labelSmall?.copyWith(
          color: cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _engineName(String engine) => switch (engine) {
  'clamav' => 'ClamAV',
  'rkhunter' => 'rkhunter',
  'chkrootkit' => 'chkrootkit',
  _ => engine,
};

String _formatSessionResults(ScanSession session) {
  if (session.results.isEmpty) {
    return '扫描结果\n'
        '引擎: ${_engineName(session.engine)}\n'
        '目标: ${_formatTarget(session.target)}\n'
        '开始: ${session.startedAt.toIso8601String()}\n'
        '结束: ${session.finishedAt?.toIso8601String() ?? '未知'}\n'
        '结果: 未发现威胁';
  }

  final buffer = StringBuffer('扫描结果\n')
    ..writeln('引擎: ${_engineName(session.engine)}')
    ..writeln('目标: ${_formatTarget(session.target)}')
    ..writeln('开始: ${session.startedAt.toIso8601String()}')
    ..writeln('结束: ${session.finishedAt?.toIso8601String() ?? '未知'}')
    ..writeln('文件: ${session.filesScanned}')
    ..writeln('威胁: ${session.threatsFound}')
    ..writeln();

  for (final result in session.results) {
    buffer
      ..writeln('状态: ${result.actionText}')
      ..writeln('威胁: ${result.threatName}')
      ..writeln('路径: ${result.filePath}')
      ..writeln('时间: ${result.timestamp.toIso8601String()}');
    if (result.details != null && result.details!.isNotEmpty) {
      buffer.writeln('详情: ${result.details}');
    }
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

String _formatSessionLogs(ScanSession session) {
  if (session.logs.isEmpty) return '暂无扫描日志';
  final engine = _engineName(session.engine);
  return session.logs.map((line) => '[$engine] $line').join('\n');
}

Future<void> _copyText(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

void _showRawLogDialog(
  BuildContext context, {
  required String title,
  required String text,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 760,
        height: 520,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copyText(dialogContext, text, '扫描日志已复制'),
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String _formatTarget(String target) => target.isEmpty ? '系统级扫描' : target;

String _formatDuration(Duration? duration) {
  if (duration == null) return '未知耗时';
  if (duration.inSeconds < 60) return '${duration.inSeconds} 秒';
  if (duration.inMinutes < 60) return '${duration.inMinutes} 分钟';
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${duration.inHours} 小时 $minutes 分钟';
}

String _formatDateTime(DateTime dateTime) {
  final y = dateTime.year.toString();
  final m = dateTime.month.toString().padLeft(2, '0');
  final d = dateTime.day.toString().padLeft(2, '0');
  final h = dateTime.hour.toString().padLeft(2, '0');
  final min = dateTime.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}
