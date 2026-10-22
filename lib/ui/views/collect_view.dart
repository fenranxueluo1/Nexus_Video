import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/domain/catalog.dart';
import '../../core/workspace/workspace_state.dart';
import '../sheets/output_choice_sheet.dart';
import '../presentation.dart';
import '../components/surfaces.dart';

class CollectView extends StatefulWidget {
  const CollectView({super.key});

  @override
  State<CollectView> createState() => _CollectViewState();
}

class _CollectViewState extends State<CollectView> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedItems = {};
  String _profileId = '';
  bool _profileInitialized = false;
  String _query = '';

  @override
  void dispose() {
    _inputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _collect(WorkspaceState app) async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    await app.collectLink(input);
  }

  Future<void> _pasteAndCollect(WorkspaceState app) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      return;
    }
    _inputController.text = text;
    await _collect(app);
  }

  Future<void> _openOutputChoice(WorkspaceState app) async {
    final result = await showDialog<OutputChoice>(
      context: context,
      builder: (context) =>
          OutputChoiceSheet(state: app, initialProfileId: _profileId),
    );
    if (result == null || !mounted) {
      return;
    }
    final outcome = await app.enqueueJobs(
      profile: result.profile,
      quality: result.quality,
      codec: result.codec,
    );
    if (!mounted || outcome == null) {
      return;
    }
    if (outcome.failures.isNotEmpty || outcome.skipped.isNotEmpty) {
      final messages = <String>[
        ...outcome.failures.map(
          (failure) => '${failure.title}：${failure.message}',
        ),
        ...outcome.skipped.map((skip) => '${skip.title}：${skip.reason}'),
      ];
      showIssueDialog(context, '生成任务结果', messages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = workspaceOf(context);
    final profiles = app.preferences.allProfiles;
    if (!_profileInitialized ||
        !profiles.any((profile) => profile.id == _profileId)) {
      _profileId = app.preferences.defaultProfileId;
      _profileInitialized = true;
      if (!profiles.any((profile) => profile.id == _profileId)) {
        _profileId = profiles.first.id;
      }
    }

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(app),
          Expanded(
            child: app.catalog == null ? _buildEmpty(app) : _buildSource(app),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WorkspaceState app) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '解析链接',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '粘贴 B 站、YouTube、X 或抖音链接，挑选要保存的内容',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  maxLines: 1,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _collect(app),
                  decoration: const InputDecoration(
                    hintText: 'BV1xx411c7mD、YouTube、X 或抖音链接',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: app.collecting ? null : () => _collect(app),
                icon: app.collecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore),
                label: Text(app.collecting ? '解析中' : '解析链接'),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: app.collecting ? null : () => _pasteAndCollect(app),
                icon: const Icon(Icons.content_paste),
                tooltip: '粘贴并解析',
              ),
            ],
          ),
          if (app.collectError != null) ...[
            const SizedBox(height: 10),
            _IssueBanner(message: app.collectError!),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(WorkspaceState app) {
    if (app.collecting) {
      return const BlankSlate(
        icon: Icons.travel_explore,
        title: '正在解析链接…',
        description: '正在获取分页与分段信息，请稍候',
      );
    }
    return BlankSlate(
      icon: Icons.add_link,
      title: '从一个链接开始',
      description:
          '支持 B 站视频/番剧/收藏夹、YouTube 视频/播放列表、X 视频帖子和抖音视频。\n登录 B 站后可解析自己的收藏夹与订阅合集。',
      action: Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: () {
              _inputController.text = 'BV1xx411c7mD';
              _collect(app);
            },
            child: const Text('试用示例'),
          ),
          if (MediaQuery.sizeOf(context).width < 980)
            OutlinedButton(
              onPressed: () => app.tabIndex.value = 2,
              child: const Text('前往账号'),
            ),
        ],
      ),
    );
  }

  Widget _buildSource(WorkspaceState app) {
    final catalog = app.catalog!;
    final entries = _filteredEntries(catalog);
    return Column(
      children: [
        _buildSourceHeader(app, catalog),
        _buildToolbar(app, catalog),
        Expanded(
          child: entries.isEmpty
              ? const BlankSlate(
                  icon: Icons.filter_alt_off,
                  title: '没有匹配的内容',
                  description: '换个关键词试试',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildItem(app, entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildSourceHeader(WorkspaceState app, MediaCatalog catalog) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArtworkThumb(
            url: catalog.coverUrl,
            width: 112,
            height: 68,
            radius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        catalog.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(_kindLabel(catalog.kind)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (catalog.creator != null && catalog.creator!.isNotEmpty)
                      catalog.creator!,
                    '${catalog.items.length} 项',
                    '${catalog.trackCount} 个分段',
                    if (catalog.hasMore) '可继续加载',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (app.pageError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    app.pageError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(WorkspaceState app, MediaCatalog catalog) {
    final theme = Theme.of(context);
    final profiles = app.preferences.allProfiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: '搜索标题或分段',
                    prefixIcon: Icon(Icons.filter_alt_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: app.allSelected ? app.clearSelection : app.selectAll,
                child: Text(app.allSelected ? '取消全选' : '全选'),
              ),
              if (catalog.hasMore)
                TextButton.icon(
                  onPressed: app.collecting ? null : app.fetchNextPage,
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('更多'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                '已选 ${app.selectedCount} 段',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('profile-$_profileId-${profiles.length}'),
                  initialValue: _profileId,
                  decoration: const InputDecoration(
                    labelText: '方案',
                    isDense: true,
                  ),
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _profileId = value);
                    }
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: app.selectedCount == 0 || app.composing
                    ? null
                    : () => _openOutputChoice(app),
                icon: const Icon(Icons.playlist_add),
                label: const Text('生成任务'),
              ),
            ],
          ),
          if (app.composing) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: app.composeProgress),
                ),
                const SizedBox(width: 10),
                Text(
                  '${app.composeDone} / ${app.composeTotal}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(WorkspaceState app, CatalogEntry item) {
    final theme = Theme.of(context);
    final tracks = _visibleTracks(item);
    final pickedTracks = tracks
        .where((track) => app.isTrackSelected(track.id))
        .length;
    final allSelected = tracks.isNotEmpty && pickedTracks == tracks.length;
    final someSelected = pickedTracks > 0 && !allSelected;
    final expanded =
        _expandedItems.contains(item.id) ||
        (_query.trim().isNotEmpty && item.tracks.length > 1);

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: item.tracks.length > 1
                ? () => setState(() {
                    if (_expandedItems.contains(item.id)) {
                      _expandedItems.remove(item.id);
                    } else {
                      _expandedItems.add(item.id);
                    }
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected ? true : (someSelected ? null : false),
                    tristate: true,
                    onChanged: (_) => app.setTracksSelected(
                      tracks.map((track) => track.id),
                      !allSelected,
                    ),
                  ),
                  ArtworkThumb(url: item.coverUrl, width: 82, height: 50),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (item.creator != null &&
                                item.creator!.isNotEmpty)
                              item.creator!,
                            if (item.durationMs > 0)
                              formatDurationMs(item.durationMs),
                            if (item.tracks.length > 1)
                              '${item.tracks.length} 个分段',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.tracks.length > 1)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
          if (item.tracks.length > 1 && expanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                children: [
                  for (final track in tracks)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 56,
                        right: 12,
                      ),
                      value: app.isTrackSelected(track.id),
                      onChanged: (_) => app.toggleTrack(track.id),
                      title: Text(
                        track.title.isEmpty ? '分段 ${track.index}' : track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(
                        [
                          '#${track.index}',
                          if (track.durationMs > 0)
                            formatDurationMs(track.durationMs),
                          if (track.cid != null) 'CID ${track.cid}',
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<CatalogEntry> _filteredEntries(MediaCatalog catalog) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return catalog.items;
    }
    return catalog.items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.tracks.any((track) => track.title.toLowerCase().contains(query));
    }).toList();
  }

  List<CatalogTrack> _visibleTracks(CatalogEntry item) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return item.tracks;
    }
    final matching = item.tracks
        .where((track) => track.title.toLowerCase().contains(query))
        .toList();
    return matching.isEmpty ? item.tracks : matching;
  }

  String _kindLabel(CatalogKind kind) {
    return switch (kind) {
      CatalogKind.video => '视频',
      CatalogKind.bangumi => '番剧',
      CatalogKind.cheese => '课程',
      CatalogKind.favorite => '收藏夹',
      CatalogKind.collectedFavorite => '订阅合集',
      CatalogKind.uploader => '创作者',
      CatalogKind.season => '合集',
      CatalogKind.series => '系列',
      CatalogKind.watchLater => '稍后再看',
      CatalogKind.tube => 'YouTube',
      CatalogKind.chirp => 'X',
      CatalogKind.douyin => '抖音',
      CatalogKind.unknown => '未知',
    };
  }
}

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
