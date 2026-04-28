import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/clamav_provider.dart';
import '../providers/theme_provider.dart';
import '../services/window_controller.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  ClamAvProvider? _provider;

  static const _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: '仪表板',
    ),
    _NavDestination(
      icon: Icons.scanner_outlined,
      selectedIcon: Icons.scanner,
      label: '扫描',
    ),
    _NavDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: '设置',
    ),
    _NavDestination(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: '历史',
    ),
  ];

  final List<Widget> _screens = const [
    DashboardScreen(),
    ScanScreen(),
    SettingsScreen(),
    HistoryScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Provider.of<ClamAvProvider>(context, listen: false);
    if (!identical(_provider, next)) {
      _provider?.removeListener(_onProviderChanged);
      _provider = next;
      _provider!.addListener(_onProviderChanged);
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    final err = _provider?.lastError;
    if (err == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    });
    _provider?.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        children: [
          _SideNav(
            selectedIndex: _selectedIndex,
            destinations: _destinations,
            onSelect: (i) => setState(() => _selectedIndex = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: _destinations[_selectedIndex].label),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _SideNav extends StatelessWidget {
  final int selectedIndex;
  final List<_NavDestination> destinations;
  final ValueChanged<int> onSelect;
  const _SideNav({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(right: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Column(
        children: [
          // Brand header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shield, color: cs.onPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'ClamFox',
                  style: tt.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // Nav items
          for (var i = 0; i < destinations.length; i++)
            _NavItem(
              destination: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          // Footer status
          Consumer<ClamAvProvider>(
            builder: (context, av, _) {
              final ok = av.isInstalled && av.databaseVersion.isNotEmpty;
              final color = ok ? cs.tertiary : cs.error;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok ? '引擎就绪' : '需要配置',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  destination.label,
                  style: tt.labelLarge?.copyWith(
                    color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => WindowController.startDrag(),
      onDoubleTap: () => WindowController.toggleMaximize(),
      child: Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(28, 0, 8, 0),
        child: Row(
          children: [
            Text(
              title,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Consumer<ClamAvProvider>(
              builder: (context, av, _) {
                final canUpdate = av.engineSupportsUpdate;
                return IconButton.filledTonal(
                  tooltip: canUpdate
                      ? '更新 ${av.activeEngine.displayName} 数据库'
                      : '${av.activeEngine.displayName} 不需要数据库更新',
                  onPressed: (av.isUpdating || !canUpdate)
                      ? null
                      : () => av.updateDatabase(),
                  icon: av.isUpdating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                );
              },
            ),
            const SizedBox(width: 8),
            Consumer<ThemeProvider>(
              builder: (context, theme, _) {
                return IconButton.filledTonal(
                  tooltip: theme.isDarkMode ? '切换到浅色' : '切换到深色',
                  onPressed: () => theme.setThemeMode(
                    theme.isDarkMode ? ThemeMode.light : ThemeMode.dark,
                  ),
                  icon: Icon(
                    theme.isDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 22, color: cs.outlineVariant),
            const SizedBox(width: 4),
            _WinButton(
              icon: Icons.minimize,
              tooltip: '最小化',
              onTap: WindowController.minimize,
            ),
            _WinButton(
              icon: Icons.crop_square,
              tooltip: '最大化',
              onTap: WindowController.toggleMaximize,
            ),
            _WinButton(
              icon: Icons.close,
              tooltip: '关闭',
              destructive: true,
              onTap: WindowController.close,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool destructive;
  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destructive = false,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverBg = widget.destructive
        ? const Color(0xFFE53935)
        : cs.surfaceContainerHighest;
    final hoverFg = widget.destructive ? Colors.white : cs.onSurface;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          child: Container(
            width: 46,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _hover ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 18,
              color: _hover ? hoverFg : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
