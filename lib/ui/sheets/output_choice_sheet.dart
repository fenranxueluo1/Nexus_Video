import 'package:flutter/material.dart';

import '../../core/domain/output_profile.dart';
import '../../core/workspace/workspace_state.dart';

class OutputChoice {
  const OutputChoice({
    required this.profile,
    required this.quality,
    required this.codec,
  });

  final OutputProfile profile;
  final String quality;
  final String codec;
}

class OutputChoiceSheet extends StatefulWidget {
  const OutputChoiceSheet({
    super.key,
    required this.state,
    required this.initialProfileId,
  });

  final WorkspaceState state;
  final String initialProfileId;

  @override
  State<OutputChoiceSheet> createState() => _OutputChoiceSheetState();
}

class _OutputChoiceSheetState extends State<OutputChoiceSheet> {
  late OutputProfile _profile;
  late String _quality;
  late String _codec;

  static const List<(String, String)> _qualityOptions = [
    ('best', '自动（最高）'),
    ('127', '8K'),
    ('120', '4K'),
    ('116', '1080P60'),
    ('80', '1080P'),
    ('74', '720P60'),
    ('64', '720P'),
    ('32', '480P'),
    ('16', '360P'),
    ('worst', '最低'),
  ];

  static const List<(String, String)> _codecOptions = [
    ('auto', '自动'),
    ('avc', 'AVC / H.264'),
    ('hevc', 'HEVC / H.265'),
    ('av1', 'AV1'),
  ];

  @override
  void initState() {
    super.initState();
    _profile = widget.state.preferences.profileById(widget.initialProfileId);
    _quality = _profile.quality;
    _codec = _profile.codec;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = widget.state.preferences.allProfiles;
    final qualityOptions = <(String, String)>[
      ..._qualityOptions,
      if (!_qualityOptions.any((option) => option.$1 == _quality) &&
          _quality.isNotEmpty)
        (_quality, _quality),
    ];
    final codecOptions = <(String, String)>[
      ..._codecOptions,
      if (!_codecOptions.any((option) => option.$1 == _codec) &&
          _codec.isNotEmpty)
        (_codec, _codec),
    ];
    return AlertDialog(
      title: const Text('输出方案'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue:
                    profiles.any((profile) => profile.id == _profile.id)
                    ? _profile.id
                    : profiles.first.id,
                decoration: const InputDecoration(labelText: '输出方案'),
                items: [
                  for (final profile in profiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(
                        '${profile.name}${profile.builtIn ? '' : '（自定义）'}',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _profile = profiles.firstWhere(
                      (profile) => profile.id == value,
                    );
                    _quality = _profile.quality;
                    _codec = _profile.codec;
                  });
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('dialog-quality-$_quality'),
                      initialValue: _quality,
                      decoration: const InputDecoration(labelText: '清晰度'),
                      items: [
                        for (final option in qualityOptions)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _quality = value ?? _quality),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('dialog-codec-$_codec'),
                      initialValue: _codec,
                      decoration: const InputDecoration(labelText: '编码'),
                      items: [
                        for (final option in codecOptions)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _codec = value ?? _codec),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('输出内容', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TagPill(label: '封装 ${_profile.container.label}'),
                  if (_profile.includeVideo) const _TagPill(label: '视频'),
                  if (_profile.includeAudio) const _TagPill(label: '音频'),
                  if (_profile.includeArtwork) const _TagPill(label: '封面'),
                  if (_profile.embedArtwork) const _TagPill(label: '嵌入封面'),
                  if (_profile.includeCaptions) const _TagPill(label: '字幕'),
                  if (_profile.embedCaptions) const _TagPill(label: '嵌入字幕'),
                  if (_profile.overlayFormats.isNotEmpty)
                    _TagPill(
                      label:
                          '弹幕 ${_profile.overlayFormats.map((format) => format.label).join('/')}',
                    ),
                  if (_profile.includeCatalog) const _TagPill(label: 'NFO'),
                  if (_profile.keepSourceStreams)
                    const _TagPill(label: '保留原始流'),
                  if (!_profile.producesMedia) const _TagPill(label: '仅附加文件'),
                ],
              ),
              const SizedBox(height: 18),
              Text('路径预览', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  widget.state.previewPathTemplate(
                    widget.state.preferences.pathTemplate,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '方案可在“设置 → 输出方案”中调整；清晰度与编码会覆盖方案值。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
          onPressed: () => Navigator.of(context).pop(
            OutputChoice(profile: _profile, quality: _quality, codec: _codec),
          ),
          child: const Text('生成任务'),
        ),
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
