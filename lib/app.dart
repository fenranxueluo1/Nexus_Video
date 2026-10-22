import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/workspace/workspace_state.dart';
import 'ui/workspace_shell.dart';
import 'ui/app_theme.dart';

class NexusApp extends StatefulWidget {
  const NexusApp({super.key});

  @override
  State<NexusApp> createState() => _NexusWorkspaceState();
}

class _NexusWorkspaceState extends State<NexusApp> {
  late Future<WorkspaceState> _future;

  @override
  void initState() {
    super.initState();
    _future = WorkspaceState.create();
  }

  void _retry() {
    setState(() {
      _future = WorkspaceState.create();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkspaceState>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        '应用初始化失败',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton(onPressed: _retry, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            home: const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在加载 Nexus视频下载器…'),
                  ],
                ),
              ),
            ),
          );
        }
        return _NexusRoot(state: snapshot.data!);
      },
    );
  }
}

class _NexusRoot extends StatelessWidget {
  const _NexusRoot({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return WorkspaceScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'Nexus视频下载器',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: switch (state.preferences.appearance) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const WorkspaceShell(),
          );
        },
      ),
    );
  }
}
