import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/engines/scan_engine.dart';
import '../models/scan_settings.dart';
import '../providers/clamav_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      children: const [
        _PrivilegedModeSection(),
        SizedBox(height: 20),
        _EngineSection(),
        SizedBox(height: 20),
        _ThemeSection(),
        SizedBox(height: 20),
        _ScanSettingsSection(),
        SizedBox(height: 20),
        _AboutSection(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Privileged mode
// ---------------------------------------------------------------------------

class _PrivilegedModeSection extends StatelessWidget {
  const _PrivilegedModeSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '特权模式',
      subtitle: '一次授权后启动特权模式服务；扫描、更新、安装均无需重复输密码',
      child: Consumer<ClamAvProvider>(
        builder: (context, av, _) {
          final cs = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;
          final enabled = av.privilegedModeEnabled;
          final starting = av.privilegedModeStarting;
          final installing = av.privilegedHelperInstalling;
          final installed = av.privilegedHelperInstalled;
          final error = av.privilegedHelperError;

          final Color statusColor;
          final IconData statusIcon;
          final String statusText;
          if (enabled) {
            statusColor = cs.primary;
            statusIcon = Icons.shield_rounded;
            statusText = '已启用 · 特权模式服务运行中';
          } else if (!installed) {
            statusColor = cs.onSurfaceVariant;
            statusIcon = Icons.download_outlined;
            statusText = '尚未安装特权模式服务';
          } else if (error != null) {
            statusColor = cs.error;
            statusIcon = Icons.error_outline;
            statusText = '启动失败：$error';
          } else {
            statusColor = cs.onSurfaceVariant;
            statusIcon = Icons.lock_outline;
            statusText = '未启用，部分操作每次都会请求授权';
          }

          Widget trailing;
          if (installing || starting) {
            trailing = const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          } else if (!installed) {
            trailing = FilledButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('安装服务'),
              onPressed: () => av.installPrivilegedHelper(),
            );
          } else {
            trailing = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: enabled,
                  onChanged: (value) async {
                    if (value) {
                      await av.enablePrivilegedMode();
                    } else {
                      await av.disablePrivilegedMode();
                    }
                  },
                ),
                IconButton(
                  tooltip: '卸载特权模式服务',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmUninstallHelper(context, av),
                ),
              ],
            );
          }

          final String hint;
          if (enabled) {
            hint = '特权模式服务已部署在系统路径，进程退出会自动回退到旧授权流程。';
          } else if (!installed) {
            hint = '点击「安装服务」会弹一次系统授权，应用将把随应用打包的特权模式服务部署到系统路径并注册系统授权策略。';
          } else {
            hint = '首次启用时会弹一次系统授权对话框；启用后扫描/更新/安装免再输密码。';
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, size: 18, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: tt.bodyMedium?.copyWith(color: statusColor),
                      ),
                    ),
                    trailing,
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> _confirmUninstallHelper(
  BuildContext context,
  ClamAvProvider av,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_outlined, size: 36),
      title: const Text('卸载特权模式服务'),
      content: const Text(
        '将删除系统路径中的特权模式服务与对应系统授权策略文件，'
        '之后扫描系统级引擎时会重新弹出密码框。是否继续？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: const Text('卸载'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  if (!context.mounted) return;
  await av.uninstallPrivilegedHelper();
}

// ---------------------------------------------------------------------------
// Section frame
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, subtitle == null ? 8 : 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Engines
// ---------------------------------------------------------------------------

class _EngineSection extends StatelessWidget {
  const _EngineSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '扫描引擎',
      subtitle: '查看每个引擎的安装状态、版本与数据库；可单独安装或更新',
      child: Consumer<ClamAvProvider>(
        builder: (context, av, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                for (final engine in av.allEngines)
                  _EngineInfoCard(engine: engine),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => av.refreshEngineAvailability(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新检测可用性'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EngineInfoCard extends StatefulWidget {
  final ScanEngine engine;
  const _EngineInfoCard({required this.engine});

  @override
  State<_EngineInfoCard> createState() => _EngineInfoCardState();
}

class _EngineInfoCardState extends State<_EngineInfoCard> {
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Consumer<ClamAvProvider>(
      builder: (context, av, _) {
        final id = widget.engine.id;
        final availability = av.availabilityOf(id);
        final installed = availability.installed;
        final supportsUpdate = av.engineSupportsUpdateFor(id);
        final databaseText = av.engineDatabaseText(id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(16),
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
                      installed
                          ? Icons.shield_outlined
                          : Icons.shield_moon_outlined,
                      color: installed ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.engine.displayName,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.engine.description,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Badge(
                      installed: installed,
                      text: installed ? (availability.version ?? '已安装') : '未安装',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 6,
                  children: [
                    _InfoRow(label: '版本', value: av.engineVersionText(id)),
                    _InfoRow(label: '签名 / 数据库', value: databaseText),
                    if (!installed && availability.hint != null)
                      _InfoRow(label: '提示', value: availability.hint!),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!installed)
                      FilledButton.icon(
                        onPressed: _installing ? null : () => _runInstall(av),
                        icon: _installing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(Icons.download, size: 18),
                        label: Text(_installing ? '安装中…' : '安装'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => av.refreshEngineAvailability(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重新检测'),
                      ),
                    const SizedBox(width: 8),
                    if (supportsUpdate)
                      FilledButton.tonalIcon(
                        onPressed: (av.isUpdating || !installed)
                            ? null
                            : () => av.updateDatabase(engineId: id),
                        icon: av.isUpdating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_download_outlined,
                                size: 18,
                              ),
                        label: Text(id == 'rkhunter' ? '更新并刷新基线' : '更新数据库'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runInstall(ClamAvProvider av) async {
    setState(() => _installing = true);
    final ok = await av.installEngine(widget.engine.id);
    if (!mounted) return;
    setState(() => _installing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${widget.engine.displayName} 安装成功'
              : '${widget.engine.displayName} 安装失败',
        ),
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(value, style: tt.bodySmall),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final bool installed;
  final String text;
  const _Badge({required this.installed, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = installed ? cs.tertiaryContainer : cs.errorContainer;
    final fg = installed ? cs.onTertiaryContainer : cs.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: tt.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '外观',
      subtitle: '选择应用主题',
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色'),
                ),
              ],
              selected: {theme.themeMode},
              onSelectionChanged: (s) => theme.setThemeMode(s.first),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan settings
// ---------------------------------------------------------------------------

class _ScanSettingsSection extends StatelessWidget {
  const _ScanSettingsSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '扫描设置',
      subtitle: '修改后立即生效，下次扫描使用',
      child: Consumer<ClamAvProvider>(
        builder: (context, av, _) {
          final s = av.scanSettings;
          void update(ScanSettings ns) => av.updateScanSettings(ns);
          return Column(
            children: [
              SwitchListTile(
                title: const Text('扫描压缩文件'),
                subtitle: const Text('检查 ZIP / RAR / TAR 等档案内部'),
                value: s.scanArchives,
                onChanged: (v) => update(s.copyWith(scanArchives: v)),
              ),
              SwitchListTile(
                title: const Text('扫描邮件'),
                subtitle: const Text('检查 mbox 等邮件文件'),
                value: s.scanEmails,
                onChanged: (v) => update(s.copyWith(scanEmails: v)),
              ),
              SwitchListTile(
                title: const Text('递归扫描子目录'),
                value: s.recursiveScan,
                onChanged: (v) => update(s.copyWith(recursiveScan: v)),
              ),
              SwitchListTile(
                title: const Text('检测 PUA'),
                subtitle: const Text('检测潜在不需要的程序'),
                value: s.detectPua,
                onChanged: (v) => update(s.copyWith(detectPua: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('自动隔离感染文件'),
                subtitle: const Text('扫描时移到隔离区'),
                value: s.quarantine,
                onChanged: (v) => update(s.copyWith(quarantine: v)),
              ),
              SwitchListTile(
                title: const Text('自动删除感染文件'),
                subtitle: Text(
                  '谨慎使用：扫描时直接删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                value: s.removeInfected,
                onChanged: (v) => update(s.copyWith(removeInfected: v)),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('最大文件大小'),
                subtitle: Text(
                  s.maxFileSize == 0 ? '无限制' : '${s.maxFileSize} MB',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showFileSizeDialog(context, s, av),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFileSizeDialog(
    BuildContext context,
    ScanSettings settings,
    ClamAvProvider provider,
  ) {
    final controller = TextEditingController(
      text: settings.maxFileSize == 0 ? '' : settings.maxFileSize.toString(),
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('最大文件大小'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('单位：MB；填 0 表示无限制'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '上限 (MB)',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text) ?? 0;
              provider.updateScanSettings(settings.copyWith(maxFileSize: v));
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      title: '关于 ClamFox',
      subtitle: '面向 Linux 桌面的现代化多引擎安全扫描器',
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.shield_outlined, color: cs.primary),
            title: const Text('版本'),
            subtitle: const Text('ClamFox 1.0.0 · Flutter / Material 3'),
          ),
          const ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('支持引擎'),
            subtitle: Text('ClamAV · rkhunter · chkrootkit'),
          ),
          const Divider(height: 1),
          const _LinkTile(
            icon: Icons.code,
            title: '源代码',
            url: 'https://github.com/glassfoxowo/clamfox',
          ),
          const _LinkTile(
            icon: Icons.bug_report_outlined,
            title: '反馈问题',
            url: 'https://github.com/glassfoxowo/clamfox/issues',
          ),
          const _LinkTile(
            icon: Icons.public,
            title: 'ClamAV 官网',
            url: 'https://www.clamav.net',
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String url;

  const _LinkTile({required this.icon, required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(url, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.copy_outlined, size: 18),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制到剪贴板: $url'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}
