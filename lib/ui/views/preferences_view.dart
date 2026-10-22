import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/api/service_exception.dart';
import '../../core/postprocess/media_packager.dart';
import '../../core/postprocess/catalog_metadata.dart';
import '../../core/domain/output_profile.dart';
import '../../core/domain/preferences.dart';
import '../../core/pathing/path_template.dart';
import '../../core/workspace/workspace_state.dart';
import '../../core/util/storage_paths.dart';
import '../../core/util/identifiers.dart';
import '../../core/util/proxy_detector.dart';
import '../components/surfaces.dart';
import '../sheets/tube_login_sheet.dart';

typedef PreferencesDirtyCheck = bool Function();
typedef PreferencesSaveAction = Future<bool> Function();

class PreferencesPanelController {
  PreferencesDirtyCheck? _isDirty;
  PreferencesSaveAction? _save;

  void attach({
    required PreferencesDirtyCheck isDirty,
    required PreferencesSaveAction save,
  }) {
    _isDirty = isDirty;
    _save = save;
  }

  void detach() {
    _isDirty = null;
    _save = null;
  }

  bool get isDirty => _isDirty?.call() ?? false;

  Future<bool> save() async {
    final action = _save;
    if (action == null) {
      return false;
    }
    return action();
  }
}

class PreferencesView extends StatefulWidget {
  const PreferencesView({super.key, this.showTitle = true, this.controller});

  final bool showTitle;
  final PreferencesPanelController? controller;

  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  final TextEditingController _destinationRoot = TextEditingController();
  final TextEditingController _packagerPath = TextEditingController();
  final TextEditingController _tubeCookiePath = TextEditingController();
  final TextEditingController _proxy = TextEditingController();
  final TextEditingController _rateLimitKb = TextEditingController();
  final TextEditingController _pathTemplate = TextEditingController();
  final TextEditingController _catalogTemplate = TextEditingController();

  WorkspaceState? _app;
  late Preferences _draft;
  bool _initialized = false;
  bool _saving = false;
  bool _probing = false;
  bool _detectingProxy = false;
  PackagerProbe? _probe;
  String? _pathError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = workspaceOf(context);
    if (identical(app, _app)) {
      return;
    }
    _app = app;
    if (!_initialized) {
      _initialized = true;
      _load(app);
    }
    widget.controller?.attach(isDirty: () => _dirty, save: () => _save(app));
  }

  void _load(WorkspaceState app) {
    _draft = app.preferences;
    _destinationRoot.text = _draft.destinationRoot;
    _packagerPath.text = _draft.packagerPath;
    _tubeCookiePath.text = _draft.tubeCookiePath;
    _proxy.text = _draft.proxy;
    _rateLimitKb.text = _draft.rateLimitBytesPerSecond > 0
        ? '${_draft.rateLimitBytesPerSecond ~/ 1024}'
        : '';
    _pathTemplate.text = _draft.pathTemplate;
    _catalogTemplate.text = _draft.catalogTemplate;
    _pathError = null;
    _probe = null;
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _destinationRoot.dispose();
    _packagerPath.dispose();
    _tubeCookiePath.dispose();
    _proxy.dispose();
    _rateLimitKb.dispose();
    _pathTemplate.dispose();
    _catalogTemplate.dispose();
    super.dispose();
  }

  Preferences _currentDraft() {
    final speedKb = (int.tryParse(_rateLimitKb.text.trim()) ?? 0)
        .clamp(0, 1 << 30)
        .toInt();
    return _draft.copyWith(
      destinationRoot: _destinationRoot.text.trim(),
      packagerPath: _packagerPath.text.trim(),
      tubeCookiePath: _tubeCookiePath.text.trim(),
      proxy: _proxy.text.trim(),
      pathTemplate: _pathTemplate.text.trim(),
      catalogTemplate: _catalogTemplate.text,
      rateLimitBytesPerSecond: speedKb * 1024,
    );
  }

  bool get _dirty {
    final app = _app;
    if (app == null) {
      return false;
    }
    return !preferencesEqual(_currentDraft(), app.preferences);
  }

  Future<bool> _save(WorkspaceState app) async {
    final preview = app.previewPathTemplate(_pathTemplate.text);
    if (preview.startsWith('路径规则错误')) {
      setState(() => _pathError = preview);
      return false;
    }
    final next = _currentDraft();
    setState(() => _saving = true);
    try {
      await app.savePreferences(next);
      if (!mounted) {
        return false;
      }
      setState(() {
        _draft = next;
        _saving = false;
      });
      app.showNotice('设置已保存');
      return true;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      app.showNotice(error.message, isError: true);
      return false;
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      app.showNotice('保存失败：$error', isError: true);
      return false;
    }
  }

  Future<void> _detectProxy() async {
    setState(() => _detectingProxy = true);
    try {
      final value = await ProxyDetector.detect();
      if (!mounted) {
        return;
      }
      if (value.isEmpty) {
        _app?.showNotice('未检测到系统代理或常见本机代理端口', isError: true);
        return;
      }
      setState(() {
        _proxy.text = value;
      });
      _app?.showNotice('已检测到代理：$value');
    } on Object catch (error) {
      _app?.showNotice('检测代理失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _detectingProxy = false);
      }
    }
  }

  Future<void> _pickDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择目录');
      if (path != null && path.isNotEmpty) {
        setState(() {
          _destinationRoot.text = path;
        });
      }
    } on Object catch (error) {
      _app?.showNotice('无法打开目录选择器：$error', isError: true);
    }
  }

  Future<void> _loginTube() async {
    try {
      final path = await showTubeLoginSheet(context);
      if (path == null || !mounted) {
        return;
      }
      setState(() {
        _tubeCookiePath.text = path;
      });
      final app = _app;
      if (app != null) {
        await _save(app);
      }
    } on Object catch (error) {
      _app?.showNotice('打开 YouTube 登录失败：$error', isError: true);
    }
  }

  Future<void> _pickTubeCookies() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Cookie 文件', extensions: ['txt', 'cookies']),
        ],
      );
      if (file != null) {
        setState(() {
          _tubeCookiePath.text = file.path;
        });
      }
    } on Object catch (error) {
      _app?.showNotice('无法打开 Cookie 文件：$error', isError: true);
    }
  }

  Future<void> _pickPackager() async {
    try {
      final typeGroup = Platform.isWindows
          ? const XTypeGroup(label: '封装工具', extensions: ['exe'])
          : const XTypeGroup(label: '可执行文件');
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        setState(() {
          _packagerPath.text = file.path;
          _probe = null;
        });
      }
    } on Object catch (error) {
      _app?.showNotice('无法打开文件选择器：$error', isError: true);
    }
  }

  Future<void> _probePackager(WorkspaceState app) async {
    setState(() {
      _probing = true;
      _probe = null;
    });
    final result = await app.probePackager(_packagerPath.text.trim());
    if (!mounted) {
      return;
    }
    setState(() {
      _probing = false;
      _probe = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = workspaceOf(context);
    final theme = Theme.of(context);
    final pathPreview = app.previewPathTemplate(_pathTemplate.text);
    final pathInvalid = pathPreview.startsWith('路径规则错误');
    if (pathInvalid && _pathError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _pathError = pathPreview);
        }
      });
    } else if (!pathInvalid && _pathError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _pathError = null);
        }
      });
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              if (widget.showTitle)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '配置保存位置、封装工具、网络与输出规则',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: () => setState(() => _load(app)),
                child: const Text('还原'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: _saving || pathInvalid ? null : () => _save(app),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? '保存中' : '保存设置'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildBasics(app),
          const SizedBox(height: 12),
          _buildTransfer(app),
          const SizedBox(height: 12),
          _buildTube(),
          const SizedBox(height: 12),
          _buildPathRules(app, pathPreview, pathInvalid),
          const SizedBox(height: 12),
          _buildCatalogMetadata(),
          const SizedBox(height: 12),
          _buildProfiles(),
          const SizedBox(height: 12),
          _buildAbout(app),
        ],
      ),
    );
  }

  Widget _buildBasics(WorkspaceState app) {
    return PanelCard(
      title: '常规',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _destinationRoot,
                  readOnly: Platform.isIOS || Platform.isAndroid,
                  decoration: InputDecoration(
                    labelText: '保存位置',
                    helperText: Platform.isIOS
                        ? 'iOS 固定使用“文件”App 中的 Nexus 目录'
                        : Platform.isAndroid
                        ? 'Android 使用应用专属目录，暂不支持选择系统其他目录'
                        : null,
                  ),
                ),
              ),
              if (!Platform.isAndroid && !Platform.isIOS) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder_open),
                  tooltip: '选择目录',
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => openContainingFolder(
                  context,
                  app,
                  _destinationRoot.text.trim(),
                ),
                icon: const Icon(Icons.open_in_new),
                tooltip: '打开目录',
              ),
            ],
          ),
          if (Platform.isIOS || Platform.isAndroid)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _destinationRoot.text = StoragePaths.defaultDownloadDir;
                }),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('恢复默认目录'),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('theme-${_draft.appearance}'),
                  initialValue: _draft.appearance,
                  decoration: const InputDecoration(labelText: '主题'),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                    DropdownMenuItem(value: 'light', child: Text('浅色')),
                    DropdownMenuItem(value: 'dark', child: Text('深色')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      appearance: value ?? _draft.appearance,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('concurrency-${_draft.parallelJobs}'),
                  initialValue: _draft.parallelJobs,
                  decoration: const InputDecoration(labelText: '并行任务数'),
                  items: [
                    for (var value = 1; value <= 5; value += 1)
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      parallelJobs: value ?? _draft.parallelJobs,
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _draft.resumeOnLaunch,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(resumeOnLaunch: value)),
            title: const Text('启动时恢复未完成任务'),
            subtitle: const Text('关闭后，上次未完成的任务会保持暂停状态'),
          ),
          if (!Platform.isIOS)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.revealAfterSave,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(revealAfterSave: value),
              ),
              title: const Text('完成后打开保存位置'),
            ),
        ],
      ),
    );
  }

  bool get _canEmbeddedTubeLogin => Platform.isWindows || Platform.isMacOS;

  Widget _buildTube() {
    final theme = Theme.of(context);
    final mobile = Platform.isIOS || Platform.isAndroid;
    final description = mobile
        ? '移动端暂不支持 yt-dlp Cookie，YouTube 仍使用纯 Dart 提取。'
        : _canEmbeddedTubeLogin
        ? '可直接在应用内登录 YouTube 获取 Cookie；内置登录使用系统代理，也可以选择已导出的 cookies.txt。'
        : '当前平台不支持内置登录，请选择浏览器导出的 Netscape cookies.txt。';
    return PanelCard(
      title: 'YouTube 登录',
      description: description,
      child: mobile
          ? Text(
              '如需在移动端使用登录态，需要接入移动端 yt-dlp 运行时。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tubeCookiePath,
                        decoration: const InputDecoration(
                          labelText: 'Cookie 文件',
                          hintText: 'cookies.txt；留空则匿名解析',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _pickTubeCookies,
                      icon: const Icon(Icons.file_open),
                      tooltip: '选择 Cookie 文件',
                    ),
                    if (_tubeCookiePath.text.trim().isNotEmpty)
                      IconButton(
                        onPressed: () => setState(_tubeCookiePath.clear),
                        icon: const Icon(Icons.clear),
                        tooltip: '清除 Cookie',
                      ),
                  ],
                ),
                if (_canEmbeddedTubeLogin) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _loginTube,
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('在应用内登录 YouTube'),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Cookie 只保存在本机凭据目录，仅用于 YouTube 请求。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTransfer(WorkspaceState app) {
    final theme = Theme.of(context);
    return PanelCard(
      title: '网络与接收',
      description: switch (Platform.operatingSystem) {
        'ios' => 'iOS 使用 AVFoundation 合并 MP4/M4A，无需 FFmpeg。',
        'android' => 'Android 使用系统 MediaMuxer 合并 MP4/M4A，无需 FFmpeg。',
        _ => '封装工具用于合并音视频；Windows 上只接受 ffmpeg.exe。',
      },
      child: Column(
        children: [
          if (Platform.isIOS || Platform.isAndroid)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '暂不支持 MKV、MP3、FLAC、字幕嵌入或封面嵌入。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _packagerPath,
                    decoration: InputDecoration(
                      labelText: '封装工具路径',
                      hintText: Platform.isWindows
                          ? '留空自动查找内置或 PATH 中的 FFmpeg'
                          : '留空自动在 PATH 中查找',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _pickPackager,
                  icon: const Icon(Icons.folder_open),
                  tooltip: '选择封装工具',
                ),
                OutlinedButton(
                  onPressed: _probing ? null : () => _probePackager(app),
                  child: Text(_probing ? '检测中' : '检测'),
                ),
              ],
            ),
            if (_probe != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _probe!.available
                      ? '可用：${_probe!.version}\n${_probe!.path}'
                      : '不可用：${_probe!.error ?? '未知错误'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _probe!.available
                        ? const Color(0xFF2E9E63)
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('segments-${_draft.normalizedSegments}'),
                  initialValue: _draft.normalizedSegments,
                  decoration: const InputDecoration(labelText: '并行分片数'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1（单连接）')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                    DropdownMenuItem(value: 8, child: Text('8')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      parallelSegments: value ?? _draft.parallelSegments,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('retries-${_draft.retryLimit}'),
                  initialValue: _draft.retryLimit.clamp(0, 5),
                  decoration: const InputDecoration(labelText: '重试上限'),
                  items: [
                    for (var value = 0; value <= 5; value += 1)
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      retryLimit: value ?? _draft.retryLimit,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _rateLimitKb,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '全局速率上限（KB/s）',
                    hintText: '0 = 不限速',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _proxy,
                  decoration: const InputDecoration(
                    labelText: 'HTTP 代理',
                    hintText: '留空自动使用系统代理；也可填 http://127.0.0.1:7897',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _detectingProxy ? null : _detectProxy,
                icon: _detectingProxy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar, size: 18),
                label: Text(_detectingProxy ? '检测中' : '自动检测'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('quality-${_draft.qualityPreference}'),
                  initialValue: _draft.qualityPreference,
                  decoration: const InputDecoration(labelText: '默认清晰度'),
                  items: const [
                    DropdownMenuItem(value: 'best', child: Text('自动最高')),
                    DropdownMenuItem(value: '80', child: Text('1080P')),
                    DropdownMenuItem(value: '64', child: Text('720P')),
                    DropdownMenuItem(value: '32', child: Text('480P')),
                    DropdownMenuItem(value: '16', child: Text('360P')),
                    DropdownMenuItem(value: 'worst', child: Text('最低')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      qualityPreference: value ?? _draft.qualityPreference,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('codec-${_draft.codecPreference}'),
                  initialValue: _draft.codecPreference,
                  decoration: const InputDecoration(labelText: '默认编码'),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('自动')),
                    DropdownMenuItem(value: 'avc', child: Text('AVC / H.264')),
                    DropdownMenuItem(
                      value: 'hevc',
                      child: Text('HEVC / H.265'),
                    ),
                    DropdownMenuItem(value: 'av1', child: Text('AV1')),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      codecPreference: value ?? _draft.codecPreference,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<CollisionPolicy>(
                  key: ValueKey('duplicate-${_draft.collisionPolicy.wire}'),
                  initialValue: _draft.collisionPolicy,
                  decoration: const InputDecoration(labelText: '重名处理'),
                  items: [
                    for (final policy in CollisionPolicy.values)
                      DropdownMenuItem(
                        value: policy,
                        child: Text(policy.label),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _draft = _draft.copyWith(
                      collisionPolicy: value ?? _draft.collisionPolicy,
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPathRules(WorkspaceState app, String preview, bool invalid) {
    final theme = Theme.of(context);
    return PanelCard(
      title: '输出路径规则',
      description: '使用 {变量} 组合输出路径，支持子目录。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pathTemplate,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '相对路径规则',
              errorText: invalid ? _pathError : null,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in templateVariableHelp.entries)
                ActionChip(
                  label: Text('{${entry.key}}'),
                  tooltip: entry.value,
                  onPressed: () {
                    final recipe = _pathTemplate.selection;
                    final text = _pathTemplate.text;
                    final insert = '{${entry.key}}';
                    final start = recipe.isValid ? recipe.start : text.length;
                    final end = recipe.isValid ? recipe.end : text.length;
                    _pathTemplate.text =
                        '${text.substring(0, start)}$insert${text.substring(end)}';
                    _pathTemplate.selection = TextSelection.collapsed(
                      offset: start + insert.length,
                    );
                    setState(() {});
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('预览', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(preview, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 6),
          Text(
            '日期变量可写成 {date:%Y-%m-%d}、{date:%Y.%m.%d} 或 {date:%Y%m%d}。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogMetadata() {
    final theme = Theme.of(context);
    return PanelCard(
      title: '媒体资料文件',
      description: '方案启用 NFO 时，会按此规则生成 .nfo 文件。留空使用内置规则。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _catalogTemplate,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(hintText: defaultCatalogTemplate),
          ),
          const SizedBox(height: 6),
          Text(
            '可用变量：{title} {track_title} {plot} {bvid} {aid} {cid} {creator} {creator_id} {publish_date} {collection} {series} {quality} {codec} {url}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfiles() {
    final theme = Theme.of(context);
    return PanelCard(
      title: '输出方案',
      description: '内置方案不可修改；自定义方案可以编辑或删除。',
      trailing: OutlinedButton.icon(
        onPressed: () => _editProfile(null),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建'),
      ),
      child: Column(
        children: [
          for (final profile in _draft.allProfiles)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    profile.builtIn ? Icons.lock_outline : Icons.tune,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              profile.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (profile.id == _draft.defaultProfileId) ...[
                              const SizedBox(width: 6),
                              const Chip(
                                label: Text('默认'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _profileSummary(profile),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!profile.builtIn)
                    IconButton(
                      onPressed: () => _editProfile(profile),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: '编辑',
                    ),
                  if (!profile.builtIn)
                    IconButton(
                      onPressed: () => _deleteProfile(profile),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: '删除',
                    ),
                  if (profile.id != _draft.defaultProfileId)
                    TextButton(
                      onPressed: () => setState(() {
                        _draft = _draft.copyWith(defaultProfileId: profile.id);
                      }),
                      child: const Text('设为默认方案'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _profileSummary(OutputProfile profile) {
    final tracks = <String>[profile.container.label];
    if (profile.includeVideo) {
      tracks.add('视频');
    }
    if (profile.includeAudio) {
      tracks.add('音频');
    }
    if (!profile.includeVideo && !profile.includeAudio) {
      tracks.add('仅附加资源');
    }
    if (profile.includeArtwork) {
      tracks.add('封面');
    }
    if (profile.embedArtwork) {
      tracks.add('嵌入封面');
    }
    if (profile.includeCaptions) {
      tracks.add('字幕');
    }
    if (profile.embedCaptions) {
      tracks.add('嵌入字幕');
    }
    if (profile.overlayFormats.isNotEmpty) {
      tracks.add(
        '弹幕 ${profile.overlayFormats.map((format) => format.label).join('/')}',
      );
    }
    if (profile.includeCatalog) {
      tracks.add('NFO');
    }
    return tracks.join(' · ');
  }

  Future<void> _editProfile(OutputProfile? initial) async {
    final profile = await showDialog<OutputProfile>(
      context: context,
      builder: (context) => _ProfileEditorSheet(
        initial: initial,
        fallbackQuality: _draft.qualityPreference,
        fallbackCodec: _draft.codecPreference,
      ),
    );
    if (profile == null) {
      return;
    }
    final profiles = List<OutputProfile>.of(_draft.profiles);
    final index = profiles.indexWhere(
      (candidate) => candidate.id == profile.id,
    );
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    setState(() {
      _draft = _draft.copyWith(profiles: profiles);
    });
  }

  Future<void> _deleteProfile(OutputProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除方案'),
        content: Text('确定删除“${profile.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final profiles = _draft.profiles
        .where((candidate) => candidate.id != profile.id)
        .toList();
    final defaultId = _draft.defaultProfileId == profile.id
        ? OutputProfile.builtins.first.id
        : _draft.defaultProfileId;
    setState(() {
      _draft = _draft.copyWith(profiles: profiles, defaultProfileId: defaultId);
    });
  }

  Future<void> _exportReport(WorkspaceState app) async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'nexus-diagnostics.zip',
      );
      if (location == null || location.path.isEmpty) {
        return;
      }
      await app.exportReport(location.path);
    } on Object catch (error) {
      app.showNotice('导出诊断报告失败：$error', isError: true);
    }
  }

  Widget _buildAbout(WorkspaceState app) {
    final theme = Theme.of(context);
    return PanelCard(
      title: '关于与诊断',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailRow(label: '应用', value: 'Nexus 0.1.0 · Flutter'),
          DetailRow(
            label: '应用数据',
            value: StoragePaths.dataDir.path,
            selectable: true,
          ),
          DetailRow(
            label: '封装工具',
            value: _packagerPath.text.trim().isEmpty
                ? '自动查找'
                : _packagerPath.text.trim(),
          ),
          DetailRow(
            label: '完成记录',
            value: '${app.coordinator.records.length} 条',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => openContainingFolder(
                  context,
                  app,
                  StoragePaths.dataDir.path,
                ),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开应用数据'),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportReport(app),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('导出诊断报告'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nexus 与哔哩哔哩无隶属关系。请仅保存你有权使用的内容。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEditorSheet extends StatefulWidget {
  const _ProfileEditorSheet({
    this.initial,
    required this.fallbackQuality,
    required this.fallbackCodec,
  });

  final OutputProfile? initial;
  final String fallbackQuality;
  final String fallbackCodec;

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _name;
  late bool _includeVideo;
  late bool _includeAudio;
  late OutputContainer _container;
  late bool _includeArtwork;
  late bool _embedArtwork;
  late bool _includeCaptions;
  late bool _embedCaptions;
  late bool _includeCatalog;
  late bool _keepSourceStreams;
  late String _quality;
  late String _codec;
  late Set<OverlayFormat> _overlayFormats;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '自定义方案');
    _includeVideo = initial?.includeVideo ?? true;
    _includeAudio = initial?.includeAudio ?? true;
    _container = initial?.container ?? OutputContainer.mp4;
    _includeArtwork = initial?.includeArtwork ?? false;
    _embedArtwork = initial?.embedArtwork ?? false;
    _includeCaptions = initial?.includeCaptions ?? false;
    _embedCaptions = initial?.embedCaptions ?? false;
    _includeCatalog = initial?.includeCatalog ?? false;
    _keepSourceStreams = initial?.keepSourceStreams ?? false;
    _quality = initial?.quality ?? widget.fallbackQuality;
    _codec = initial?.codec ?? widget.fallbackCodec;
    _overlayFormats = initial?.overlayFormatSet ?? {};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新建输出方案' : '编辑输出方案'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '方案名称'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('profile-quality-$_quality'),
                      initialValue: _quality,
                      decoration: const InputDecoration(labelText: '清晰度'),
                      items: const [
                        DropdownMenuItem(value: 'best', child: Text('自动最高')),
                        DropdownMenuItem(value: '80', child: Text('1080P')),
                        DropdownMenuItem(value: '64', child: Text('720P')),
                        DropdownMenuItem(value: '32', child: Text('480P')),
                        DropdownMenuItem(value: '16', child: Text('360P')),
                        DropdownMenuItem(value: 'worst', child: Text('最低')),
                      ],
                      onChanged: (value) =>
                          setState(() => _quality = value ?? _quality),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('profile-codec-$_codec'),
                      initialValue: _codec,
                      decoration: const InputDecoration(labelText: '编码'),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('自动')),
                        DropdownMenuItem(value: 'avc', child: Text('AVC')),
                        DropdownMenuItem(value: 'hevc', child: Text('HEVC')),
                        DropdownMenuItem(value: 'av1', child: Text('AV1')),
                      ],
                      onChanged: (value) =>
                          setState(() => _codec = value ?? _codec),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<OutputContainer>(
                      key: ValueKey(
                        'profile-container-${_container.extension}',
                      ),
                      initialValue: _container,
                      decoration: const InputDecoration(labelText: '容器'),
                      items: [
                        for (final format in OutputContainer.values)
                          DropdownMenuItem(
                            value: format,
                            child: Text(format.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _container = value ?? _container),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeVideo,
                onChanged: (value) => setState(() => _includeVideo = value),
                title: const Text('保存视频流'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeAudio,
                onChanged: (value) => setState(() => _includeAudio = value),
                title: const Text('保存音频流'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeArtwork,
                onChanged: (value) => setState(() => _includeArtwork = value),
                title: const Text('保存封面'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _embedArtwork,
                onChanged: (value) => setState(() => _embedArtwork = value),
                title: const Text('嵌入封面（仅 MKV）'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeCaptions,
                onChanged: (value) => setState(() => _includeCaptions = value),
                title: const Text('保存字幕（SRT）'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _embedCaptions,
                onChanged: (value) => setState(() => _embedCaptions = value),
                title: const Text('嵌入字幕（仅 MKV）'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeCatalog,
                onChanged: (value) => setState(() => _includeCatalog = value),
                title: const Text('生成媒体资料文件'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _keepSourceStreams,
                onChanged: (value) =>
                    setState(() => _keepSourceStreams = value),
                title: const Text('保留原始音视频流'),
                subtitle: const Text('完成后不删除临时文件'),
              ),
              const SizedBox(height: 6),
              Text('弹幕格式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final format in OverlayFormat.values)
                    FilterChip(
                      label: Text(format.label),
                      selected: _overlayFormats.contains(format),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _overlayFormats.add(format);
                        } else {
                          _overlayFormats.remove(format);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final profile = OutputProfile(
              id: widget.initial?.id ?? makeId('profile'),
              name: _name.text.trim().isEmpty ? '自定义方案' : _name.text.trim(),
              builtIn: false,
              includeVideo: _includeVideo,
              includeAudio: _includeAudio,
              quality: _quality,
              codec: _codec,
              container: _container,
              includeArtwork: _includeArtwork,
              embedArtwork: _embedArtwork,
              includeCaptions: _includeCaptions,
              embedCaptions: _embedCaptions,
              overlayFormats: _overlayFormats.toList(),
              keepRawOverlay: _overlayFormats.contains(OverlayFormat.xml),
              includeCatalog: _includeCatalog,
              keepSourceStreams: _keepSourceStreams,
            );
            Navigator.of(context).pop(profile);
          },
          child: const Text('保存方案'),
        ),
      ],
    );
  }
}
