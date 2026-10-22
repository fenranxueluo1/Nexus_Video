import 'package:flutter/material.dart';

import '../core/workspace/workspace_state.dart';
import 'views/account_view.dart';
import 'views/collect_view.dart';
import 'views/jobs_view.dart';
import 'views/preferences_view.dart';

enum _PreferencesCloseAction { cancel, discard, save }

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  WorkspaceState? _state;
  int _lastNoticeSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.detached) {
      _state?.coordinator.shutdown();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = workspaceOf(context);
    if (identical(state, _state)) {
      return;
    }
    _state?.removeListener(_onStateChanged);
    _state = state;
    _lastNoticeSeq = state.noticeSeq;
    state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    final state = _state;
    if (state == null || state.noticeSeq == _lastNoticeSeq) {
      return;
    }
    _lastNoticeSeq = state.noticeSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(state.notice ?? ''),
          backgroundColor: state.noticeIsError
              ? Theme.of(context).colorScheme.error
              : null,
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state?.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = workspaceOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final jobPaneWidth = constraints.maxWidth >= 1400
            ? 480.0
            : (constraints.maxWidth >= 1100 ? 420.0 : 360.0);
        return ValueListenableBuilder<int>(
          valueListenable: state.tabIndex,
          builder: (context, index, _) {
            final tab = index.clamp(0, 2);
            return Scaffold(
              appBar: _buildAppBar(context, state, wide),
              body: wide
                  ? Row(
                      children: [
                        const Expanded(child: CollectView()),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: jobPaneWidth,
                          child: const JobsView(active: true),
                        ),
                      ],
                    )
                  : IndexedStack(
                      index: tab,
                      children: [
                        const CollectView(),
                        JobsView(active: tab == 1),
                        const AccountView(),
                      ],
                    ),
              bottomNavigationBar: wide ? null : _buildBottomBar(state, tab),
            );
          },
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context, WorkspaceState state, bool wide) {
    final theme = Theme.of(context);
    return AppBar(
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 10),
          const Text('Nexus视频下载器'),
        ],
      ),
      actions: [
        ListenableBuilder(
          listenable: state.coordinator,
          builder: (context, _) {
            final running = state.coordinator.runningCount;
            if (running == 0) {
              return const SizedBox.shrink();
            }
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$running 个运行中',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        if (wide)
          TextButton.icon(
            onPressed: () => _showPanel(
              context,
              title: '账号',
              child: const AccountView(showTitle: false),
            ),
            icon: Icon(
              state.isLoggedIn ? Icons.person : Icons.person_outline,
              size: 18,
            ),
            label: Text(state.isLoggedIn ? state.account.name : '登录'),
          ),
        IconButton(
          onPressed: () => _showPreferencesPanel(context),
          icon: const Icon(Icons.tune),
          tooltip: '设置',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomBar(WorkspaceState state, int index) {
    return ListenableBuilder(
      listenable: state.coordinator,
      builder: (context, _) {
        return NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => state.tabIndex.value = value,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.travel_explore_outlined),
              selectedIcon: Icon(Icons.travel_explore),
              label: '解析链接',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: state.coordinator.runningCount > 0,
                label: Text('${state.coordinator.runningCount}'),
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: const Icon(Icons.download),
              label: '任务',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '账号',
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPreferencesPanel(BuildContext context) async {
    final controller = PreferencesPanelController();
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _requestPreferencesClose(dialogContext, controller);
            }
          },
          child: Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: size.width < 700 ? 8 : 24,
              vertical: size.height < 700 ? 8 : 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 980,
                maxHeight: size.height - 48,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          '设置',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _requestPreferencesClose(
                            dialogContext,
                            controller,
                          ),
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: PreferencesView(
                      showTitle: false,
                      controller: controller,
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

  Future<void> _requestPreferencesClose(
    BuildContext dialogContext,
    PreferencesPanelController controller,
  ) async {
    if (!controller.isDirty) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      return;
    }
    final action = await showDialog<_PreferencesCloseAction>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('保存更改？'),
        content: const Text('设置中有未保存的更改。关闭前是否保存？'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PreferencesCloseAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PreferencesCloseAction.discard),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_PreferencesCloseAction.save),
            child: const Text('保存并关闭'),
          ),
        ],
      ),
    );
    if (action == null || action == _PreferencesCloseAction.cancel) {
      return;
    }
    if (action == _PreferencesCloseAction.save) {
      final saved = await controller.save();
      if (!saved) {
        return;
      }
    }
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  void _showPanel(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final size = MediaQuery.sizeOf(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 700 ? 8 : 24,
            vertical: size.height < 700 ? 8 : 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 980,
              maxHeight: size.height - 48,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }
}
