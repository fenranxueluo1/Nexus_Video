import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/domain/jobs.dart';
import '../../core/workspace/workspace_state.dart';

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description != null && description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class BlankSlate extends StatelessWidget {
  const BlankSlate({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.state});

  final JobState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (state) {
      JobState.finished => const Color(0xFF2E9E63),
      JobState.failed => theme.colorScheme.error,
      JobState.transferring ||
      JobState.packaging ||
      JobState.preparing => theme.colorScheme.primary,
      JobState.held => const Color(0xFFD08A1E),
      JobState.aborted => theme.colorScheme.onSurfaceVariant,
      JobState.queued => theme.colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        state.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ArtworkThumb extends StatelessWidget {
  const ArtworkThumb({
    super.key,
    this.url,
    this.width = 96,
    this.height = 60,
    this.radius = 8,
  });

  final String? url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
    final normalized = _normalize(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: normalized == null
          ? placeholder
          : Image.network(
              normalized,
              width: width,
              height: height,
              fit: BoxFit.cover,
              headers: const {'Referer': 'https://www.bilibili.com/'},
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }

  static String? _normalize(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    var url = value.trim();
    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    return url;
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueWidget = selectable
        ? SelectableText(value, style: theme.textTheme.bodySmall)
        : Text(value, style: theme.textTheme.bodySmall);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

void showIssueDialog(
  BuildContext context,
  String title,
  List<String> messages,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: messages.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('• ${messages[index]}'),
            ),
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

Future<void> openContainingFolder(
  BuildContext context,
  WorkspaceState app,
  String path,
) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await showFolderContentsDialog(context, app: app, path: path);
    return;
  }
  await app.revealInFolder(path);
}

Future<void> showFolderContentsDialog(
  BuildContext context, {
  required WorkspaceState app,
  required String path,
}) async {
  final normalized = p.normalize(p.absolute(path));
  final fileExists = await File(normalized).exists();
  final directory = fileExists ? p.dirname(normalized) : normalized;
  if (!await Directory(directory).exists()) {
    app.showNotice('目标文件夹不存在：$directory', isError: true);
    return;
  }
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _FolderBrowserDialog(initialPath: directory, app: app),
  );
}

class _FolderBrowserDialog extends StatefulWidget {
  const _FolderBrowserDialog({required this.initialPath, required this.app});

  final String initialPath;
  final WorkspaceState app;

  @override
  State<_FolderBrowserDialog> createState() => _FolderBrowserDialogState();
}

class _FolderBrowserDialogState extends State<_FolderBrowserDialog> {
  late String _path;
  late Future<List<FileSystemEntity>> _entries;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _entries = _list(_path);
  }

  Future<List<FileSystemEntity>> _list(String path) async {
    final entries = await Directory(path).list().toList();
    entries.sort((left, right) {
      final leftDirectory = left is Directory;
      final rightDirectory = right is Directory;
      if (leftDirectory != rightDirectory) {
        return leftDirectory ? -1 : 1;
      }
      return p
          .basename(left.path)
          .toLowerCase()
          .compareTo(p.basename(right.path).toLowerCase());
    });
    return entries;
  }

  void _navigate(String path) {
    setState(() {
      _path = path;
      _entries = _list(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parent = p.dirname(_path);
    final height = MediaQuery.sizeOf(context).height;
    final contentHeight = height < 600 ? height * 0.6 : 420.0;
    return AlertDialog(
      title: const Text('文件夹'),
      content: SizedBox(
        width: 560,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: parent == _path ? null : () => _navigate(parent),
                  child: const Text('上一级'),
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: FutureBuilder<List<FileSystemEntity>>(
                future: _entries,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '无法读取文件夹：${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <FileSystemEntity>[];
                  if (items.isEmpty) {
                    return const Center(child: Text('文件夹为空'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entity = items[index];
                      final isDirectory = entity is Directory;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isDirectory
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                        ),
                        title: Text(
                          p.basename(entity.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: isDirectory
                            ? () => _navigate(entity.path)
                            : () => widget.app.openPath(entity.path),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (Platform.isAndroid || Platform.isIOS)
          TextButton(
            onPressed: () async {
              await widget.app.copyFolderToDownloads(_path);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(Platform.isIOS ? '导出到文件' : '复制到下载目录'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
