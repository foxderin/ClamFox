import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan_result.dart';
import '../providers/clamav_provider.dart';

class RecentScansCard extends StatelessWidget {
  const RecentScansCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        if (av.scanResults.isEmpty) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final shown = av.scanResults.take(5).toList();
        final more = av.scanResults.length - shown.length;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Text(
                    '最近威胁',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => av.clearScanResults(),
                    child: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...shown.map((r) => _Row(result: r)),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '还有 $more 条结果，可在「扫描 → 结果」查看',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final ScanResult result;
  const _Row({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (icon, color) = switch (result.action) {
      ScanAction.detected => (Icons.warning_amber_outlined, cs.error),
      ScanAction.removed => (Icons.delete_outline, cs.tertiary),
      ScanAction.quarantined => (Icons.shield_outlined, cs.primary),
      ScanAction.skipped => (Icons.skip_next_outlined, cs.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.threatName,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  result.filePath,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _MiniEngineChip(engine: result.engine),
          const SizedBox(width: 8),
          Text(
            result.actionText,
            style: tt.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniEngineChip extends StatelessWidget {
  final String engine;
  const _MiniEngineChip({required this.engine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (label, fg, bg) = switch (engine) {
      'clamav' => ('ClamAV', cs.onPrimaryContainer, cs.primaryContainer),
      'rkhunter' => (
          'rkhunter',
          cs.onSecondaryContainer,
          cs.secondaryContainer,
        ),
      'chkrootkit' => (
          'chkrootkit',
          cs.onTertiaryContainer,
          cs.tertiaryContainer,
        ),
      _ => (engine, cs.onSurfaceVariant, cs.surfaceContainerHighest),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
