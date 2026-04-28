import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/engines/scan_engine.dart';
import '../providers/clamav_provider.dart';
import '../services/polkit_service.dart';
import '../widgets/recent_scans_card.dart';
import '../widgets/scan_status_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        if (!av.hasAnyEngineInstalled) return _NotInstalledView(provider: av);
        return _InstalledDashboard(av: av);
      },
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

class _InstalledDashboard extends StatelessWidget {
  final ClamAvProvider av;
  const _InstalledDashboard({required this.av});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      children: [
        _HeroStatus(av: av),
        const SizedBox(height: 20),
        _StatsRow(av: av),
        const SizedBox(height: 20),
        if (av.activeEngine.supportsPathScan) const _ActionsPanel(),
        if (av.activeEngine.supportsPathScan) const SizedBox(height: 20),
        if (!av.activeEngine.supportsPathScan) _SystemEngineCard(av: av),
        if (!av.activeEngine.supportsPathScan) const SizedBox(height: 20),
        if (av.isScanning) const ScanStatusCard(),
        if (av.isScanning) const SizedBox(height: 20),
        if (av.scanResults.isNotEmpty) const RecentScansCard(),
      ],
    );
  }
}

class _SystemEngineCard extends StatelessWidget {
  final ClamAvProvider av;
  const _SystemEngineCard({required this.av});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final engine = av.activeEngine;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.policy_outlined,
              color: cs.onPrimaryContainer,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${engine.displayName} · 系统级检查',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  engine.description,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: av.isScanning ? null : () => av.scanPath(''),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始扫描'),
          ),
        ],
      ),
    );
  }
}

class _HeroStatus extends StatelessWidget {
  final ClamAvProvider av;
  const _HeroStatus({required this.av});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasThreats = av.threatsFound > 0;
    final scanning = av.isScanning;

    final bg = hasThreats
        ? cs.errorContainer
        : (scanning ? cs.tertiaryContainer : cs.primaryContainer);
    final fg = hasThreats
        ? cs.onErrorContainer
        : (scanning ? cs.onTertiaryContainer : cs.onPrimaryContainer);
    final title = hasThreats
        ? '发现 ${av.threatsFound} 个威胁'
        : (scanning ? '正在扫描' : '系统受保护');
    final last = av.lastSession;
    final subtitle = hasThreats
        ? '建议立即处置威胁文件'
        : (scanning
              ? (av.filesScanned == 0
                    ? '正在加载病毒库（首次启动需 20–60 秒）'
                    : '已扫描 ${av.filesScanned} 个文件')
              : (last != null
                    ? '上次扫描 · ${_relativeTime(last.startedAt)} · '
                          '${last.filesScanned} 个文件'
                    : '当前引擎 ${av.activeEngine.displayName}'));
    final iconData = hasThreats
        ? Icons.dangerous_outlined
        : (scanning
              ? Icons.shield_moon_outlined
              : Icons.verified_user_outlined);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(iconData, size: 40, color: fg),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.headlineSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: tt.bodyMedium?.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final ClamAvProvider av;
  const _StatsRow({required this.av});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: '已扫描文件',
            value: av.filesScanned.toString(),
            icon: Icons.folder_open_outlined,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatTile(
            label: '检出威胁',
            value: av.threatsFound.toString(),
            icon: Icons.bug_report_outlined,
            color: av.threatsFound > 0 ? cs.error : cs.tertiary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatTile(
            label: '病毒库',
            value: av.databaseVersion.isEmpty ? '—' : av.databaseVersion,
            icon: Icons.shield_outlined,
            color: cs.secondary,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 14),
          Text(
            value,
            style: tt.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

enum _ActionTarget { folder, file, home, full }

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('快速扫描', style: tt.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                child: _ActionTile(
                  icon: Icons.folder_open_outlined,
                  label: '文件夹',
                  target: _ActionTarget.folder,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: '单个文件',
                  target: _ActionTarget.file,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.home_outlined,
                  label: '主目录',
                  target: _ActionTarget.home,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.public,
                  label: '全盘',
                  target: _ActionTarget.full,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final _ActionTarget target;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        final disabled = av.isScanning;
        return Material(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled ? null : () => _handle(context, av),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: disabled ? cs.onSurfaceVariant : cs.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: tt.labelMedium?.copyWith(
                      color: disabled ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handle(BuildContext context, ClamAvProvider av) async {
    switch (target) {
      case _ActionTarget.folder:
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir != null) await av.scanPath(dir);
        break;
      case _ActionTarget.file:
        final result = await FilePicker.platform.pickFiles();
        final path = result?.files.single.path;
        if (path != null) await av.scanPath(path);
        break;
      case _ActionTarget.home:
        final home = Platform.environment['HOME'] ?? '/home';
        await av.scanPath(home);
        break;
      case _ActionTarget.full:
        if (!context.mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmFullScanDialog(),
        );
        if (ok == true) await av.scanPath('/');
        break;
    }
  }
}

class _ConfirmFullScanDialog extends StatelessWidget {
  const _ConfirmFullScanDialog();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_outlined, size: 36),
      title: const Text('全盘扫描'),
      content: const Text('全盘扫描可能耗时数小时，期间可随时取消。是否继续？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开始'),
        ),
      ],
    );
  }
}

class _NotInstalledView extends StatelessWidget {
  final ClamAvProvider provider;
  const _NotInstalledView({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  size: 44,
                  color: cs.onErrorContainer,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '尚未安装任何扫描引擎',
                        style: tt.headlineSmall?.copyWith(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '至少安装一个引擎才能开始使用，可按需选择',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => provider.refreshEngineAvailability(),
                icon: const Icon(Icons.refresh),
                label: const Text('重新检查'),
              ),
              TextButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _ManualInstallSheet(),
                ),
                icon: const Icon(Icons.help_outline),
                label: const Text('查看手动安装命令'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final engine in provider.allEngines) ...[
            _EngineInstallTile(engine: engine, provider: provider),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _EngineInstallTile extends StatefulWidget {
  final ScanEngine engine;
  final ClamAvProvider provider;
  const _EngineInstallTile({required this.engine, required this.provider});

  @override
  State<_EngineInstallTile> createState() => _EngineInstallTileState();
}

class _EngineInstallTileState extends State<_EngineInstallTile> {
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final availability = widget.provider.availabilityOf(widget.engine.id);
    final installed = availability.installed;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: installed ? cs.tertiaryContainer : cs.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              installed ? Icons.verified : Icons.download_outlined,
              color: installed ? cs.onTertiaryContainer : cs.onErrorContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.engine.displayName,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: installed
                            ? cs.tertiaryContainer
                            : cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        installed ? (availability.version ?? '已安装') : '未安装',
                        style: tt.labelSmall?.copyWith(
                          color: installed
                              ? cs.onTertiaryContainer
                              : cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  installed
                      ? widget.engine.description
                      : (availability.hint ?? widget.engine.description),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!installed)
            FilledButton.icon(
              onPressed: _installing ? null : _runInstall,
              icon: _installing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.download),
              label: Text(_installing ? '安装中…' : '一键安装'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => widget.provider.refreshEngineAvailability(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测'),
            ),
        ],
      ),
    );
  }

  Future<void> _runInstall() async {
    setState(() => _installing = true);
    final ok = await widget.provider.installEngine(widget.engine.id);
    if (!mounted) return;
    setState(() => _installing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '${widget.engine.displayName} 安装成功' : '安装失败，可尝试手动命令',
        ),
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String label;
  final String code;
  const _CodeBlock({required this.label, required this.code});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SelectableText(
            code,
            style: tt.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualInstallSheet extends StatelessWidget {
  const _ManualInstallSheet();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.help_outline, size: 36),
      title: const Text('手动安装扫描引擎'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在终端中按发行版选择对应命令：'),
              const SizedBox(height: 16),
              const _CodeBlock(
                label: 'Ubuntu / Debian',
                code:
                    'sudo apt install clamav clamav-daemon clamav-freshclam\n'
                    'sudo apt install rkhunter chkrootkit\n'
                    'sudo freshclam',
              ),
              const SizedBox(height: 12),
              const _CodeBlock(
                label: 'Arch Linux',
                code:
                    'sudo pacman -S clamav rkhunter chkrootkit\n'
                    'sudo freshclam',
              ),
              const SizedBox(height: 12),
              const _CodeBlock(
                label: 'Fedora / RHEL',
                code:
                    'sudo dnf install clamav clamav-update rkhunter chkrootkit\n'
                    'sudo freshclam',
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await PolkitService.installPolkitPolicy();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '系统授权策略已安装' : '系统授权策略安装失败')),
                  );
                },
                icon: const Icon(Icons.shield),
                label: const Text('安装系统授权策略文件'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
