import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/engines/scan_engine.dart';
import '../models/scan_result.dart';
import '../providers/clamav_provider.dart';

enum _ScanTab { setup, results }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  _ScanTab _tab = _ScanTab.setup;
  final Set<String> _selectedEngines = {};
  bool _selectionInitialized = false;

  void _ensureDefaultSelection(ClamAvProvider av) {
    if (_selectionInitialized) return;
    // System-level engines (rkhunter / chkrootkit) launch directly from
    // their tile, so they don't participate in the selection set — only
    // pre-select path-scan engines.
    final installed = av.allEngines
        .where((e) => av.isEngineInstalled(e.id) && e.supportsPathScan)
        .map((e) => e.id)
        .toSet();
    if (installed.isNotEmpty) {
      _selectedEngines
        ..clear()
        ..addAll(installed);
      _selectionInitialized = true;
    }
  }

  void _toggleEngine(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedEngines.add(id);
      } else {
        _selectedEngines.remove(id);
      }
    });
  }

  Future<void> _startPathScan(ClamAvProvider av, String path) async {
    final pathEngines = _selectedEngines.where((id) {
      final engine = av.allEngines.firstWhere(
        (e) => e.id == id,
        orElse: () => av.allEngines.first,
      );
      return engine.supportsPathScan;
    }).toSet();
    if (pathEngines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在「路径扫描」中至少勾选一个引擎')));
      return;
    }
    await av.scanWithEngines(path, pathEngines);
  }

  Future<void> _startSystemScan(ClamAvProvider av, String engineId) async {
    if (!av.isEngineInstalled(engineId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该引擎未安装，请先安装后再扫描')));
      return;
    }
    await av.scanWithEngines('', {engineId});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_ScanTab>(
            segments: const [
              ButtonSegment(
                value: _ScanTab.setup,
                icon: Icon(Icons.scanner_outlined),
                label: Text('扫描'),
              ),
              ButtonSegment(
                value: _ScanTab.results,
                icon: Icon(Icons.fact_check_outlined),
                label: Text('结果'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _tab == _ScanTab.setup
                ? _ScanSetupView(
                    selectedEngines: _selectedEngines,
                    onSelectionChanged: _toggleEngine,
                    onEnsureDefault: _ensureDefaultSelection,
                    onStartPathScan: _startPathScan,
                    onStartSystemScan: _startSystemScan,
                  )
                : const _ResultsView(),
          ),
        ],
      ),
    );
  }
}

class _ScanSetupView extends StatelessWidget {
  final Set<String> selectedEngines;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(ClamAvProvider av) onEnsureDefault;
  final Future<void> Function(ClamAvProvider av, String path) onStartPathScan;
  final Future<void> Function(ClamAvProvider av, String engineId)
  onStartSystemScan;

  const _ScanSetupView({
    required this.selectedEngines,
    required this.onSelectionChanged,
    required this.onEnsureDefault,
    required this.onStartPathScan,
    required this.onStartSystemScan,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        onEnsureDefault(av);
        if (av.isScanning) return _MultiEngineProgress(av: av);
        return _ScanSetupBody(
          av: av,
          selectedEngines: selectedEngines,
          onSelectionChanged: onSelectionChanged,
          onStartPathScan: onStartPathScan,
          onStartSystemScan: onStartSystemScan,
        );
      },
    );
  }
}

class _ScanSetupBody extends StatelessWidget {
  final ClamAvProvider av;
  final Set<String> selectedEngines;
  final void Function(String id, bool selected) onSelectionChanged;
  final Future<void> Function(ClamAvProvider av, String path) onStartPathScan;
  final Future<void> Function(ClamAvProvider av, String engineId)
  onStartSystemScan;

  const _ScanSetupBody({
    required this.av,
    required this.selectedEngines,
    required this.onSelectionChanged,
    required this.onStartPathScan,
    required this.onStartSystemScan,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pathEngines = av.allEngines.where((e) => e.supportsPathScan).toList();
    final systemEngines = av.allEngines
        .where((e) => !e.supportsPathScan)
        .toList();

    return ListView(
      children: [
        // ---- Path scan section ----
        _ScanModeHeader(
          icon: Icons.folder_open_outlined,
          title: '路径扫描',
          subtitle: '对指定文件、目录或全盘做病毒匹配',
          color: cs.primary,
        ),
        const SizedBox(height: 12),
        if (pathEngines.isEmpty)
          _MutedHint(text: '没有可用的路径扫描引擎，请先安装 ClamAV')
        else
          for (final engine in pathEngines)
            _EngineCheckTile(
              engine: engine,
              installed: av.isEngineInstalled(engine.id),
              selected: selectedEngines.contains(engine.id),
              availabilityHint: av.availabilityOf(engine.id).hint,
              onChanged: (v) => onSelectionChanged(engine.id, v),
            ),
        const SizedBox(height: 8),
        _TargetTile(
          icon: Icons.folder_open_outlined,
          title: '扫描文件夹',
          subtitle: '选择特定目录递归扫描',
          color: cs.primary,
          onTap: () async {
            final dir = await FilePicker.platform.getDirectoryPath();
            if (dir != null) await onStartPathScan(av, dir);
          },
        ),
        _TargetTile(
          icon: Icons.insert_drive_file_outlined,
          title: '扫描单个文件',
          subtitle: '挑选一个文件进行检测',
          color: cs.primary,
          onTap: () async {
            final r = await FilePicker.platform.pickFiles();
            final path = r?.files.single.path;
            if (path != null) await onStartPathScan(av, path);
          },
        ),
        _TargetTile(
          icon: Icons.home_outlined,
          title: '扫描主目录',
          subtitle: r'$HOME 下所有用户文件',
          color: cs.secondary,
          onTap: () =>
              onStartPathScan(av, Platform.environment['HOME'] ?? '/home'),
        ),
        _TargetTile(
          icon: Icons.public,
          title: '全盘扫描',
          subtitle: '从 / 开始，可能耗时数小时',
          color: cs.error,
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                icon: const Icon(Icons.warning_amber_outlined, size: 36),
                title: const Text('全盘扫描'),
                content: const Text('全盘扫描可能耗时数小时，期间可随时取消。是否继续？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('开始'),
                  ),
                ],
              ),
            );
            if (ok == true) await onStartPathScan(av, '/');
          },
        ),

        const SizedBox(height: 28),

        // ---- System scan section ----
        _ScanModeHeader(
          icon: Icons.policy_outlined,
          title: '系统级扫描',
          subtitle: 'rootkit / 后门检测；按引擎内置规则扫整个系统，不需要选路径',
          color: cs.tertiary,
        ),
        const SizedBox(height: 12),
        if (systemEngines.isEmpty)
          _MutedHint(text: '没有可用的系统级扫描引擎，请先安装 rkhunter 或 chkrootkit')
        else
          for (final engine in systemEngines)
            _SystemEngineLaunchTile(
              engine: engine,
              installed: av.isEngineInstalled(engine.id),
              availabilityHint: av.availabilityOf(engine.id).hint,
              color: cs.tertiary,
              onLaunch: () => onStartSystemScan(av, engine.id),
            ),
      ],
    );
  }
}

class _SystemEngineLaunchTile extends StatelessWidget {
  final ScanEngine engine;
  final bool installed;
  final String? availabilityHint;
  final Color color;
  final VoidCallback onLaunch;

  const _SystemEngineLaunchTile({
    required this.engine,
    required this.installed,
    required this.availabilityHint,
    required this.color,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: installed ? onLaunch : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.shield_outlined, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engine.displayName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        installed
                            ? '点击开始：${engine.description}'
                            : (availabilityHint ?? '未检测到该引擎，请先安装命令行工具'),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!installed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '未安装',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanModeHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _ScanModeHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MutedHint extends StatelessWidget {
  final String text;
  const _MutedHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _EngineCheckTile extends StatelessWidget {
  final ScanEngine engine;
  final bool installed;
  final bool selected;
  final String? availabilityHint;
  final ValueChanged<bool> onChanged;

  const _EngineCheckTile({
    required this.engine,
    required this.installed,
    required this.selected,
    required this.availabilityHint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: installed ? () => onChanged(!selected) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: installed ? (v) => onChanged(v ?? false) : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engine.displayName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        installed
                            ? (engine.supportsPathScan
                                  ? engine.description
                                  : '${engine.description} · 系统级扫描')
                            : (availabilityHint ?? '未检测到该引擎，请先安装命令行工具'),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!installed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '未安装',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiEngineProgress extends StatelessWidget {
  final ClamAvProvider av;
  const _MultiEngineProgress({required this.av});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final running = av.engineScanSnapshots
        .where((s) => s.isScanning || s.error != null || s.results.isNotEmpty)
        .toList();
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正在扫描',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                av.currentScanPath.isEmpty ? '系统级扫描' : av.currentScanPath,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: av.scanProgress,
                borderRadius: BorderRadius.circular(8),
                minHeight: 6,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Counter(
                    label: '已扫描',
                    value: av.filesScanned,
                    color: cs.primary,
                  ),
                  _Counter(
                    label: '威胁',
                    value: av.threatsFound,
                    color: av.threatsFound > 0 ? cs.error : cs.tertiary,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => av.cancelScan(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止扫描'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final snap in running) ...[
          _EngineProgressCard(snapshot: snap),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _EngineProgressCard extends StatelessWidget {
  final EngineScanSnapshot snapshot;
  const _EngineProgressCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                snapshot.isScanning
                    ? Icons.sync
                    : (snapshot.error != null
                          ? Icons.error_outline
                          : Icons.check_circle_outline),
                color: snapshot.error != null ? cs.error : cs.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  snapshot.engineName,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                snapshot.isScanning ? '运行中' : '完成',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.currentPath.isEmpty ? '系统级扫描' : snapshot.currentPath,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (snapshot.isScanning)
            LinearProgressIndicator(
              value: snapshot.progress,
              minHeight: 4,
              borderRadius: BorderRadius.circular(6),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('文件: ${snapshot.filesScanned}'),
              Text('威胁: ${snapshot.threatsFound}'),
              if (snapshot.error != null)
                Text(
                  '错误: ${snapshot.error}',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _TargetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Counter({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          value.toString(),
          style: tt.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        final results = av.scanResults;
        final logs = av.scanLogs;
        if (results.isEmpty && logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.verified_outlined,
                    size: 48,
                    color: cs.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '没有发现威胁',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '你的系统目前是干净的',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScanOutputHeader(
              resultCount: results.length,
              logCount: logs.length,
              hasThreats: results.isNotEmpty,
              onClear: results.isEmpty ? null : () => av.clearScanResults(),
              onCopyResults: () =>
                  _copyText(context, _formatScanResults(results), '扫描结果已复制'),
              onCopyLogs: logs.isEmpty
                  ? null
                  : () => _copyText(context, _formatScanLogs(logs), '扫描日志已复制'),
              onShowRawLogs: logs.isEmpty
                  ? null
                  : () => _showRawLogDialog(
                      context,
                      title: 'Raw 扫描日志',
                      text: _formatScanLogs(logs),
                    ),
            ),
            const SizedBox(height: 16),
            if (results.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    '未发现威胁；可查看或复制 Raw 日志',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ResultCard(result: results[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScanOutputHeader extends StatelessWidget {
  final int resultCount;
  final int logCount;
  final bool hasThreats;
  final VoidCallback? onClear;
  final VoidCallback onCopyResults;
  final VoidCallback? onCopyLogs;
  final VoidCallback? onShowRawLogs;

  const _ScanOutputHeader({
    required this.resultCount,
    required this.logCount,
    required this.hasThreats,
    required this.onClear,
    required this.onCopyResults,
    required this.onCopyLogs,
    required this.onShowRawLogs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = hasThreats ? cs.errorContainer : cs.tertiaryContainer;
    final fg = hasThreats ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasThreats ? Icons.warning_amber_outlined : Icons.verified_outlined,
            color: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasThreats
                      ? '检出 $resultCount 个威胁 · $logCount 行日志'
                      : '未发现威胁 · $logCount 行日志',
                  style: tt.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: onCopyResults,
                      style: TextButton.styleFrom(foregroundColor: fg),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('复制结果'),
                    ),
                    TextButton.icon(
                      onPressed: onCopyLogs,
                      style: TextButton.styleFrom(foregroundColor: fg),
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                      label: const Text('复制日志'),
                    ),
                    TextButton.icon(
                      onPressed: onShowRawLogs,
                      style: TextButton.styleFrom(foregroundColor: fg),
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('Raw 日志'),
                    ),
                    if (onClear != null)
                      TextButton(
                        onPressed: onClear,
                        style: TextButton.styleFrom(foregroundColor: fg),
                        child: const Text('清空'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatScanResults(List<ScanResult> results) {
  if (results.isEmpty) return '未发现威胁';
  final buffer = StringBuffer('扫描结果\n');
  for (final result in results) {
    buffer
      ..writeln('引擎: ${_engineName(result.engine)}')
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

String _formatScanLogs(List<String> logs) =>
    logs.isEmpty ? '暂无扫描日志' : logs.join('\n');

String _engineName(String engine) => switch (engine) {
  'clamav' => 'ClamAV',
  'rkhunter' => 'rkhunter',
  'chkrootkit' => 'chkrootkit',
  _ => engine,
};

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

class _EngineChip extends StatelessWidget {
  final String engine;
  const _EngineChip({required this.engine});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  const _ResultCard({required this.result});

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
    final canHandleFile =
        result.engine == 'clamav' && result.filePath.startsWith('/');

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.threatName,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.filePath,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.details != null && result.details!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.details!,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _EngineChip(engine: result.engine),
            const SizedBox(width: 4),
            Text(
              result.actionText,
              style: tt.labelMedium?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
              onSelected: (v) async {
                final p = Provider.of<ClamAvProvider>(context, listen: false);
                switch (v) {
                  case 'delete':
                    await p.deleteThreat(result);
                    break;
                  case 'quarantine':
                    await p.quarantineThreat(result);
                    break;
                  case 'ignore':
                    p.ignoreThreat(result);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (canHandleFile)
                  const PopupMenuItem(value: 'delete', child: Text('删除文件')),
                if (canHandleFile)
                  const PopupMenuItem(value: 'quarantine', child: Text('隔离')),
                const PopupMenuItem(value: 'ignore', child: Text('忽略')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
