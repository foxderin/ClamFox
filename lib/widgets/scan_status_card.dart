import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/clamav_provider.dart';

class ScanStatusCard extends StatelessWidget {
  const ScanStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        if (!av.isScanning) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final loadingDb = av.filesScanned == 0 && av.threatsFound == 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    loadingDb ? '正在加载病毒库' : '正在扫描',
                    style: tt.titleMedium?.copyWith(
                      color: cs.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => av.cancelScan(),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onTertiaryContainer,
                    ),
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('停止'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: av.scanProgress,
                  minHeight: 6,
                  backgroundColor:
                      cs.onTertiaryContainer.withValues(alpha: 0.15),
                  color: cs.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loadingDb
                    ? '首次启动通常需要 20–60 秒'
                    : av.currentScanPath,
                style: tt.bodySmall?.copyWith(
                  color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已扫描 ${av.filesScanned} 个文件',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    '威胁 ${av.threatsFound}',
                    style: tt.bodySmall?.copyWith(
                      color: av.threatsFound > 0
                          ? cs.error
                          : cs.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
