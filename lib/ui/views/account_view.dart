import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/service_exception.dart';
import '../../core/api/bili_gateway.dart';
import '../../core/workspace/workspace_state.dart';
import '../components/surfaces.dart';
import '../sheets/tube_login_sheet.dart';

class AccountView extends StatefulWidget {
  const AccountView({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final TextEditingController _cookieController = TextEditingController();
  WorkspaceState? _state;
  bool _autoLoadRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = workspaceOf(context);
    if (identical(state, _state)) {
      return;
    }
    _state = state;
    if (state.isLoggedIn &&
        state.accountCollections == null &&
        !state.collectionsLoading &&
        !_autoLoadRequested) {
      _autoLoadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          state.loadCollections();
        }
      });
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _importCookie(WorkspaceState app) async {
    final success = await app.loginWithCookie(_cookieController.text);
    if (success) {
      _cookieController.clear();
      setState(() => _autoLoadRequested = false);
      await app.loadCollections();
    }
  }

  bool get _canWebLogin => Platform.isWindows || Platform.isMacOS;

  bool get _canDouyinLogin =>
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isAndroid ||
      Platform.isIOS;

  Future<void> _loginYouTube(WorkspaceState app) async {
    try {
      final path = await showTubeLoginSheet(context);
      if (path == null || !mounted) {
        return;
      }
      await app.savePreferences(app.preferences.copyWith(tubeCookiePath: path));
      if (!mounted) {
        return;
      }
      setState(() {});
      app.showNotice('YouTube Cookie 已保存');
    } on ApiException catch (error) {
      app.showNotice(error.message, isError: true);
    } on Object catch (error) {
      app.showNotice('YouTube 登录失败：$error', isError: true);
    }
  }

  Future<void> _loginChirp(WorkspaceState app) async {
    try {
      final path = await showChirpLoginSheet(context);
      if (path == null || !mounted) {
        return;
      }
      await app.savePreferences(
        app.preferences.copyWith(chirpCookiePath: path),
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      app.showNotice('X Cookie 已保存');
    } on ApiException catch (error) {
      app.showNotice(error.message, isError: true);
    } on Object catch (error) {
      app.showNotice('X 登录失败：$error', isError: true);
    }
  }

  Widget _buildTubeButton(WorkspaceState app) {
    final loggedIn = app.preferences.tubeCookiePath.isNotEmpty;
    return FilledButton.tonalIcon(
      onPressed: () => _loginYouTube(app),
      icon: const Icon(Icons.smart_display_outlined, size: 18),
      label: Text(loggedIn ? '重新登录 YouTube' : '登录 YouTube'),
    );
  }

  Widget _buildChirpButton(WorkspaceState app) {
    final loggedIn = app.preferences.chirpCookiePath.isNotEmpty;
    return FilledButton.tonalIcon(
      onPressed: () => _loginChirp(app),
      icon: const Icon(Icons.alternate_email, size: 18),
      label: Text(loggedIn ? '重新登录 X' : '登录 X'),
    );
  }

  Future<void> _loginDouyin(WorkspaceState app) async {
    try {
      final path = await showDouyinLoginSheet(context);
      if (path == null || !mounted) {
        return;
      }
      await app.savePreferences(
        app.preferences.copyWith(douyinCookiePath: path),
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      app.showNotice('抖音 Cookie 已保存');
    } on ApiException catch (error) {
      app.showNotice(error.message, isError: true);
    } on Object catch (error) {
      app.showNotice('抖音登录失败：$error', isError: true);
    }
  }

  Widget _buildDouyinButton(WorkspaceState app) {
    final loggedIn = app.preferences.douyinCookiePath.isNotEmpty;
    return FilledButton.tonalIcon(
      onPressed: () => _loginDouyin(app),
      icon: const Icon(Icons.music_note, size: 18),
      label: Text(loggedIn ? '重新登录抖音' : '登录抖音'),
    );
  }

  Widget _buildRemoteLoginCard(WorkspaceState app) {
    return PanelCard(
      title: 'YouTube / X / 抖音账号',
      description: '应用内网页登录，Cookie 只保存在本机。',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (_canWebLogin) _buildTubeButton(app),
          if (_canWebLogin) _buildChirpButton(app),
          if (_canDouyinLogin) _buildDouyinButton(app),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = workspaceOf(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              if (widget.showTitle)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '账号',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '登录后查看收藏夹、订阅合集与合集系列',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              if (app.isLoggedIn)
                OutlinedButton.icon(
                  onPressed: app.collectionsLoading
                      ? null
                      : () => app.loadCollections(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!app.isLoggedIn) _buildLogin(app) else _buildLibrary(app),
        ],
      ),
    );
  }

  Widget _buildLogin(WorkspaceState app) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          title: '账号登录',
          description: 'B 站扫码登录；YouTube、X 与抖音使用应用内网页登录，登录态只保存在本机。',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _showQrLogin(app),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('获取 B 站登录二维码'),
              ),
              if (_canWebLogin) _buildTubeButton(app),
              if (_canWebLogin) _buildChirpButton(app),
              if (_canDouyinLogin) _buildDouyinButton(app),
              TextButton(
                onPressed: () => app.openPath('https://www.bilibili.com'),
                child: const Text('打开 Bilibili'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PanelCard(
          title: '导入 Cookie',
          description: '也可以从浏览器复制 Cookie 后粘贴到这里。需要包含 SESSDATA（或 bili_jct）。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _cookieController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'SESSDATA=...; bili_jct=...; DedeUserID=...',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _importCookie(app),
                    child: const Text('导入并登录'),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Cookie 等同于账号登录态，请勿分享。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (app.accountError != null) ...[
          const SizedBox(height: 12),
          Text(
            app.accountError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLibrary(WorkspaceState app) {
    final theme = Theme.of(context);
    final collections = app.accountCollections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: app.account.avatar.isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person),
                        )
                      : Image.network(
                          app.account.avatar,
                          headers: const {
                            'Referer': 'https://www.bilibili.com/',
                          },
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.person),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.account.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'UID ${app.account.mid}${app.account.vipLabel.isNotEmpty ? ' · ${app.account.vipLabel}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: app.logout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出登录'),
              ),
            ],
          ),
        ),
        if (_canWebLogin || _canDouyinLogin) ...[
          const SizedBox(height: 12),
          _buildRemoteLoginCard(app),
        ],
        if (app.collectionsError != null) ...[
          const SizedBox(height: 10),
          Text(
            app.collectionsError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (app.collectionsLoading && collections == null) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          const Center(child: Text('正在加载账号内容…')),
        ],
        if (collections != null) ...[
          const SizedBox(height: 16),
          _buildFolderSection(
            app,
            title: '收藏夹',
            description: '点击任意收藏夹载入到解析链接页',
            folders: collections.ownFolders,
          ),
          const SizedBox(height: 16),
          _buildFolderSection(
            app,
            title: '订阅合集',
            description: '来自其他创作者的收藏夹',
            folders: collections.collectedFolders,
          ),
          const SizedBox(height: 16),
          _buildCollectionSection(app, collections.collections),
        ],
        if (collections == null && !app.collectionsLoading) ...[
          const SizedBox(height: 16),
          PanelCard(
            title: '账号',
            child: Center(
              child: OutlinedButton(
                onPressed: () => app.loadCollections(),
                child: const Text('加载账号内容'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFolderSection(
    WorkspaceState app, {
    required String title,
    required String description,
    required List<FavoriteFolder> folders,
  }) {
    final theme = Theme.of(context);
    return PanelCard(
      title: title,
      description: description,
      child: folders.isEmpty
          ? Text(
              '暂无内容',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final folder in folders)
                  _LibraryTile(
                    title: folder.title,
                    subtitle:
                        '${folder.mediaCount} 个内容'
                        '${folder.creator.isNotEmpty ? ' · ${folder.creator}' : ''}',
                    coverUrl: folder.cover,
                    onTap: () => app.openFolder(folder),
                  ),
              ],
            ),
    );
  }

  Widget _buildCollectionSection(
    WorkspaceState app,
    List<SpaceCollection> collections,
  ) {
    final theme = Theme.of(context);
    return PanelCard(
      title: '我的合集',
      description: '来自当前账号空间页的合集和系列',
      child: collections.isEmpty
          ? Text(
              '暂无内容',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final collection in collections)
                  _LibraryTile(
                    title: collection.title,
                    subtitle:
                        '${collection.kind == 'season' ? '合集' : '系列'} · ${collection.count} 个视频',
                    coverUrl: collection.cover,
                    onTap: () => app.openCollection(collection),
                  ),
              ],
            ),
    );
  }

  Future<void> _showQrLogin(WorkspaceState app) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QrLoginDialog(state: app),
    );
    if (app.isLoggedIn) {
      _autoLoadRequested = false;
      await app.loadCollections();
    }
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ArtworkThumb(url: coverUrl, width: 72, height: 48),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrLoginDialog extends StatefulWidget {
  const _QrLoginDialog({required this.state});

  final WorkspaceState state;

  @override
  State<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<_QrLoginDialog> {
  QrLoginTicket? _ticket;
  String _status = '正在获取二维码…';
  bool _expired = false;
  bool _polling = false;
  bool _success = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _ticket = null;
      _expired = false;
      _success = false;
      _status = '正在获取二维码…';
    });
    try {
      final ticket = await widget.state.startQrLogin();
      if (!mounted) {
        return;
      }
      setState(() {
        _ticket = ticket;
        _status = '请使用哔哩哔哩客户端扫码';
      });
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _status = '获取失败：${error.message}');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _status = '获取失败：$error');
      }
    }
  }

  Future<void> _poll() async {
    final ticket = _ticket;
    if (ticket == null || _polling || _success || _expired) {
      return;
    }
    _polling = true;
    try {
      final result = await widget.state.pollQrLogin(ticket.key);
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        _success = true;
        _timer?.cancel();
        setState(() => _status = '登录成功');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      if (result.isExpired) {
        _expired = true;
        _timer?.cancel();
        setState(() => _status = '二维码已过期，请刷新');
        return;
      }
      setState(() {
        _status = result.isScanned
            ? '已扫码，请在手机上确认登录'
            : (result.message.isEmpty ? '等待扫码…' : result.message);
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _status = '查询失败：${error.message}');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _status = '查询失败：$error');
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('扫码登录'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_ticket != null && !_expired)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: _ticket!.url,
                  version: QrVersions.auto,
                  size: 210,
                  backgroundColor: Colors.white,
                ),
              )
            else
              const SizedBox(
                height: 210,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 14),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '登录信息仅保存在本机凭据文件中',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _start, child: const Text('刷新二维码')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
