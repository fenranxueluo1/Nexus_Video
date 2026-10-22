import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/transfer/transfer_coordinator.dart';
import '../../core/domain/jobs.dart';
import '../../core/workspace/workspace_state.dart';
import '../presentation.dart';
import '../components/surfaces.dart';

enum _JobFilter { all, active, waiting, completed, failed }

class JobsView extends StatefulWidget {
  const JobsView({super.key, this.active = true});

  final bool active;

  @override
  State<JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<JobsView> {
  _JobFilter _filter = _JobFilter.all;
  final Map<String, int> _lastBytes = {};
  Map<String, double> _speeds = {};
  Timer? _ticker;
  WorkspaceState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = workspaceOf(context);
    if (identical(state, _state)) {
      return;
    }
    _state = state;
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateSpeeds(state.coordinator),
    );
  }

  void _updateSpeeds(TransferCoordinator coordinator) {
    if (!widget.active) {
      for (final job in coordinator.jobs) {
        _lastBytes[job.id] = job.receivedBytes;
      }
      _speeds = {};
      return;
    }
    final next = <String, double>{};
    final taskIds = <String>{};
    for (final job in coordinator.jobs) {
      taskIds.add(job.id);
      if (job.state == JobState.transferring) {
        final previous = _lastBytes[job.id] ?? job.receivedBytes;
        final delta = job.receivedBytes - previous;
        if (delta > 0) {
          next[job.id] = delta.toDouble();
        }
      }
      _lastBytes[job.id] = job.receivedBytes;
    }
    _lastBytes.removeWhere((id, _) => !taskIds.contains(id));
    if (mounted) {
      setState(() => _speeds = next);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = workspaceOf(context);
    if (!widget.active) {
      return SafeArea(child: _buildContent(app));
    }
    return ListenableBuilder(
      listenable: app.coordinator,
      builder: (context, _) => SafeArea(child: _buildContent(app)),
    );
  }

  Widget _buildContent(WorkspaceState app) {
    final jobs = _filteredJobs(app.coordinator);
    final totalSpeed = _speeds.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final runningCount = app.coordinator.jobs
        .where((job) => job.state.isRunning)
        .length;
    return Column(
      children: [
        _buildHeader(app, totalSpeed, runningCount),
        Expanded(
          child: jobs.isEmpty
              ? const BlankSlate(
                  icon: Icons.download_done,
                  title: '队列为空',
                  description: '在“解析链接”区挑选内容后生成任务',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildJobCard(app, jobs[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(WorkspaceState app, double totalSpeed, int runningCount) {
    final theme = Theme.of(context);
    final counts = <_JobFilter, int>{
      _JobFilter.all: app.coordinator.jobs.length,
      _JobFilter.active: app.coordinator.jobs
          .where((job) => job.state.isRunning)
          .length,
      _JobFilter.waiting: app.coordinator.jobs
          .where(
            (job) => job.state == JobState.queued || job.state == JobState.held,
          )
          .length,
      _JobFilter.completed: app.coordinator.jobs
          .where((job) => job.state == JobState.finished)
          .length,
      _JobFilter.failed: app.coordinator.jobs
          .where(
            (job) =>
                job.state == JobState.failed || job.state == JobState.aborted,
          )
          .length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '任务',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      runningCount > 0
                          ? '$runningCount 个任务运行中 · ${formatSpeed(totalSpeed)}'
                          : '所有任务已空闲 · 已完成 ${counts[_JobFilter.completed]} 个',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showRecords(app),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('记录'),
              ),
              IconButton(
                onPressed:
                    app.coordinator.jobs.any((job) => job.state.isSettled)
                    ? () => _purgeSettled(app)
                    : null,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                tooltip: '清理已结束',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in [
                (_JobFilter.all, '所有'),
                (_JobFilter.active, '运行中'),
                (_JobFilter.waiting, '待处理'),
                (_JobFilter.completed, '已完成'),
                (_JobFilter.failed, '异常'),
              ])
                ChoiceChip(
                  label: Text('${entry.$2} ${counts[entry.$1] ?? 0}'),
                  selected: _filter == entry.$1,
                  onSelected: (_) => setState(() => _filter = entry.$1),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(WorkspaceState app, TransferJob job) {
    final theme = Theme.of(context);
    final speed = _speeds[job.id] ?? 0;
    final progress = job.progress;
    final total = job.expectedBytes;
    final hasMedia = job.recipe.includeVideo || job.recipe.includeAudio;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: job.state == JobState.failed
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showJobSheet(app, job.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StateBadge(state: job.state),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (speed > 0)
                    Text(
                      formatSpeed(speed),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (value) => _onAction(app, job, value),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('查看详情'),
                      ),
                      if (hasMedia)
                        const PopupMenuItem(value: 'open', child: Text('打开文件')),
                      const PopupMenuItem(
                        value: 'folder',
                        child: Text('打开所在文件夹'),
                      ),
                      if ((Platform.isAndroid || Platform.isIOS) &&
                          job.state == JobState.finished)
                        PopupMenuItem(
                          value: 'copy',
                          child: Text(Platform.isIOS ? '导出到文件' : '复制到下载目录'),
                        ),
                      const PopupMenuItem(value: 'speed', child: Text('任务限速')),
                      const PopupMenuItem(value: 'delete', child: Text('移除任务')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: job.state == JobState.finished
                    ? 1
                    : (job.state.isRunning
                          ? (progress > 0 ? progress : null)
                          : progress),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    total > 0
                        ? '${formatBytes(job.receivedBytes)} / ${formatBytes(total)}'
                        : (hasMedia
                              ? formatBytes(job.receivedBytes)
                              : '${job.assets.length} 个资源'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (job.state == JobState.finished)
                    Text(
                      '${job.recipe.container.label} · ${formatBytes(job.deliveredBytes)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      '${(progress * 100).clamp(0, 100).toStringAsFixed(progress > 0 ? 1 : 0)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (job.error != null && job.state == JobState.failed) ...[
                const SizedBox(height: 6),
                Text(
                  job.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  if (job.state == JobState.transferring ||
                      job.state == JobState.packaging ||
                      job.state == JobState.preparing)
                    _actionButton(
                      Icons.pause,
                      '暂停',
                      () => app.coordinator.holdJob(job.id),
                    ),
                  if (job.state == JobState.held)
                    _actionButton(
                      Icons.play_arrow,
                      '继续',
                      () => app.coordinator.releaseJob(job.id),
                    ),
                  if (job.state == JobState.failed)
                    _actionButton(
                      Icons.refresh,
                      '重试',
                      () => app.coordinator.retryJob(job.id),
                    ),
                  if (job.state == JobState.queued)
                    _actionButton(
                      Icons.close,
                      '取消',
                      () => app.coordinator.abortJob(job.id),
                    ),
                  if (job.state == JobState.finished && hasMedia)
                    _actionButton(
                      Icons.open_in_new,
                      '打开',
                      () => app.openPath(job.destination),
                    ),
                  if (job.state == JobState.finished)
                    _actionButton(
                      Icons.folder_open,
                      '所在文件夹',
                      () => openContainingFolder(context, app, job.destination),
                    ),
                  if (job.state == JobState.finished ||
                      job.state == JobState.failed ||
                      job.state == JobState.aborted)
                    _actionButton(
                      Icons.delete_outline,
                      '移除',
                      () => _confirmDelete(app, job),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
      ),
    );
  }

  void _onAction(WorkspaceState app, TransferJob job, String action) {
    switch (action) {
      case 'details':
        _showJobSheet(app, job.id);
      case 'open':
        app.openPath(job.destination);
      case 'folder':
        openContainingFolder(context, app, job.destination);
      case 'copy':
        app.copyFolderToDownloads(job.destination);
      case 'speed':
        _showSpeedLimit(app, job);
      case 'delete':
        _confirmDelete(app, job);
    }
  }

  Future<void> _showSpeedLimit(WorkspaceState app, TransferJob job) async {
    final controller = TextEditingController(
      text: job.rateLimitBytesPerSecond == null
          ? ''
          : '${job.rateLimitBytesPerSecond! ~/ 1024}',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('任务限速'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '限速（KB/s）',
            hintText: '留空或 0 表示不限制',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(context).pop(value <= 0 ? -1 : value * 1024);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) {
      return;
    }
    app.coordinator.limitJob(job.id, result < 0 ? null : result);
  }

  Future<void> _confirmDelete(WorkspaceState app, TransferJob job) async {
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('移除任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteFiles,
                onChanged: (value) =>
                    setDialogState(() => deleteFiles = value ?? false),
                title: const Text('同时删除已生成的文件'),
                subtitle: const Text('包含输出文件、字幕、弹幕、封面与临时文件'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await app.coordinator.discardJob(job.id, deleteFiles: deleteFiles);
    }
  }

  Future<void> _purgeSettled(WorkspaceState app) async {
    final deleteFiles = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理已结束任务'),
        content: const Text('将移除已完成、失败和已取消的任务记录。是否同时删除磁盘上的输出文件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('仅清除记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
    if (deleteFiles == null) {
      return;
    }
    await app.coordinator.purgeSettled(deleteFiles: deleteFiles);
  }

  void _showJobSheet(WorkspaceState app, String jobId) {
    showDialog<void>(
      context: context,
      builder: (context) => _JobDetailSheet(jobId: jobId),
    );
  }

  void _showRecords(WorkspaceState app) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('完成记录'),
        content: SizedBox(
          width: 600,
          child: app.coordinator.records.isEmpty
              ? const SizedBox(
                  height: 120,
                  child: Center(child: Text('暂无完成记录')),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: app.coordinator.records.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = app.coordinator.records[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${formatTimestamp(record.completedAt)} · ${record.container.toUpperCase()} · ${record.destination}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () => openContainingFolder(
                            context,
                            app,
                            record.destination,
                          ),
                          child: const Text('打开目录'),
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  List<TransferJob> _filteredJobs(TransferCoordinator coordinator) {
    final jobs = coordinator.jobs.where((job) {
      return switch (_filter) {
        _JobFilter.all => true,
        _JobFilter.active => job.state.isRunning,
        _JobFilter.waiting =>
          job.state == JobState.queued || job.state == JobState.held,
        _JobFilter.completed => job.state == JobState.finished,
        _JobFilter.failed =>
          job.state == JobState.failed || job.state == JobState.aborted,
      };
    }).toList();
    jobs.sort((left, right) {
      final rank = _stateRank(left.state).compareTo(_stateRank(right.state));
      if (rank != 0) {
        return rank;
      }
      final leftTime = left.createdAt?.millisecondsSinceEpoch ?? 0;
      final rightTime = right.createdAt?.millisecondsSinceEpoch ?? 0;
      return rightTime.compareTo(leftTime);
    });
    return jobs;
  }

  int _stateRank(JobState state) {
    return switch (state) {
      JobState.transferring || JobState.packaging || JobState.preparing => 0,
      JobState.queued => 1,
      JobState.held => 2,
      JobState.failed => 3,
      JobState.finished => 4,
      JobState.aborted => 5,
    };
  }
}

class _JobDetailSheet extends StatelessWidget {
  const _JobDetailSheet({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final app = workspaceOf(context);
    return ListenableBuilder(
      listenable: app.coordinator,
      builder: (context, _) {
        final job = app.coordinator.jobs.cast<TransferJob?>().firstWhere(
          (candidate) => candidate?.id == jobId,
          orElse: () => null,
        );
        if (job == null) {
          return AlertDialog(
            title: const Text('任务详情'),
            content: const Text('任务已被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        }
        final mediaHeight = MediaQuery.sizeOf(context).height;
        final contentHeight = mediaHeight < 700 ? mediaHeight * 0.55 : 460.0;
        final theme = Theme.of(context);
        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StateBadge(state: job.state),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: contentHeight,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DetailRow(label: '输出路径', value: job.destination),
                  DetailRow(
                    label: '清晰度 / 编码',
                    value: '${job.recipe.quality} / ${job.recipe.codec}',
                  ),
                  DetailRow(label: '容器', value: job.recipe.container.label),
                  if (job.scheduledAt != null)
                    DetailRow(
                      label: '计划时间',
                      value: formatTimestamp(job.scheduledAt),
                    ),
                  if (job.error != null)
                    DetailRow(label: '错误', value: job.error!),
                  const Divider(height: 24),
                  Text(
                    '资源 (${job.assets.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildResources(context, job),
                  const Divider(height: 24),
                  Text(
                    '日志 (${job.journal.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildLogs(context, job),
                ],
              ),
            ),
          ),
          actions: [
            if (job.state == JobState.transferring ||
                job.state == JobState.packaging)
              TextButton(
                onPressed: () => app.coordinator.holdJob(job.id),
                child: const Text('暂停'),
              ),
            if (job.state == JobState.held)
              TextButton(
                onPressed: () => app.coordinator.releaseJob(job.id),
                child: const Text('继续'),
              ),
            if (job.state == JobState.failed)
              TextButton(
                onPressed: () => app.coordinator.retryJob(job.id),
                child: const Text('重试'),
              ),
            if (job.recipe.includeVideo || job.recipe.includeAudio)
              TextButton(
                onPressed: () => app.openPath(job.destination),
                child: const Text('打开文件'),
              ),
            TextButton(
              onPressed: () =>
                  openContainingFolder(context, app, job.destination),
              child: const Text('打开文件夹'),
            ),
            if ((Platform.isAndroid || Platform.isIOS) &&
                job.state == JobState.finished)
              TextButton(
                onPressed: () => app.copyFolderToDownloads(job.destination),
                child: Text(Platform.isIOS ? '导出到文件' : '复制到下载目录'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResources(BuildContext context, TransferJob job) {
    final theme = Theme.of(context);
    if (job.assets.isEmpty) {
      return const Text('没有资源');
    }
    return Column(
      children: [
        for (final asset in job.assets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_intentIcon(asset.role), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              asset.label == null
                                  ? asset.role.label
                                  : '${asset.role.label} · ${asset.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _assetStateLabel(asset),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value:
                            asset.expectedBytes != null &&
                                asset.expectedBytes! > 0
                            ? (asset.receivedBytes / asset.expectedBytes!)
                                  .clamp(0.0, 1.0)
                            : (asset.state == AssetState.ready ? 1 : null),
                      ),
                      if (asset.error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          asset.error!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _assetStateLabel(JobAsset asset) {
    final bytes = formatBytes(asset.receivedBytes);
    return switch (asset.state) {
      AssetState.queued => '待处理',
      AssetState.transferring => '传输中 · $bytes',
      AssetState.ready => '完成 · $bytes',
      AssetState.failed => '失败',
      AssetState.aborted => '已取消',
      AssetState.held => '暂停',
    };
  }

  Widget _buildLogs(BuildContext context, TransferJob job) {
    final theme = Theme.of(context);
    if (job.journal.isEmpty) {
      return const Text('暂无日志');
    }
    final start = job.journal.length > 50 ? job.journal.length - 50 : 0;
    final logs = job.journal.sublist(start).reversed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (start > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '仅显示最近 50 条，共 ${job.journal.length} 条',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final log in logs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    '${log.at.hour.toString().padLeft(2, '0')}:${log.at.minute.toString().padLeft(2, '0')}:${log.at.second.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    log.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: switch (log.level) {
                        JournalLevel.error => theme.colorScheme.error,
                        JournalLevel.warning => const Color(0xFFD08A1E),
                        JournalLevel.info => theme.colorScheme.onSurfaceVariant,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _intentIcon(AssetRole role) {
    return switch (role) {
      AssetRole.video => Icons.movie_outlined,
      AssetRole.audio => Icons.music_note_outlined,
      AssetRole.artwork => Icons.image_outlined,
      AssetRole.caption => Icons.subtitles_outlined,
      AssetRole.overlay => Icons.chat_bubble_outline,
      AssetRole.catalog => Icons.description_outlined,
    };
  }
}
