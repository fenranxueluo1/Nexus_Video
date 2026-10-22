import 'dart:convert';

import 'package:xml/xml.dart';

class CommentOverlay {
  const CommentOverlay({
    required this.time,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.text,
  });

  final double time;
  final int mode;
  final int fontSize;
  final int color;
  final String text;

  bool get isSupported =>
      mode == 1 || mode == 2 || mode == 3 || mode == 4 || mode == 5;
}

List<CommentOverlay> readCommentOverlay(String xml) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return const [];
  }
  final items = <CommentOverlay>[];
  for (final element in document.findAllElements('d')) {
    final p = element.getAttribute('p');
    if (p == null || p.isEmpty) {
      continue;
    }
    final tracks = p.split(',');
    if (tracks.length < 4) {
      continue;
    }
    final time = double.tryParse(tracks[0]);
    final mode = int.tryParse(tracks[1]);
    if (time == null || mode == null) {
      continue;
    }
    final text = element.innerText.trim();
    if (text.isEmpty) {
      continue;
    }
    items.add(
      CommentOverlay(
        time: time,
        mode: mode,
        fontSize: int.tryParse(tracks[2]) ?? 25,
        color: int.tryParse(tracks[3]) ?? 0xffffff,
        text: text,
      ),
    );
  }
  items.sort((left, right) => left.time.compareTo(right.time));
  return items;
}

String _srtTime(double seconds) {
  final totalMs = (seconds * 1000).round().clamp(0, 1 << 31);
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs % 3600000) ~/ 60000;
  final secs = (totalMs % 60000) ~/ 1000;
  final millis = totalMs % 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(secs)},${millis.toString().padLeft(3, '0')}';
}

String overlayToSrt(List<CommentOverlay> items) {
  final supported = items.where((item) => item.isSupported).toList();
  final buffer = StringBuffer();
  var index = 1;
  for (final item in supported) {
    final text = item.text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    buffer.writeln(index);
    buffer.writeln('${_srtTime(item.time)} --> ${_srtTime(item.time + 4)}');
    buffer.writeln(text);
    buffer.writeln();
    index += 1;
  }
  return buffer.toString();
}

String _assTime(double seconds) {
  final totalCs = (seconds * 100).round().clamp(0, 1 << 31);
  final hours = totalCs ~/ 360000;
  final minutes = (totalCs % 360000) ~/ 6000;
  final secs = (totalCs % 6000) ~/ 100;
  final cs = totalCs % 100;
  String two(int value) => value.toString().padLeft(2, '0');
  return '$hours:${two(minutes)}:${two(secs)}.${two(cs)}';
}

String assColor(int rgb) {
  final red = (rgb >> 16) & 0xff;
  final green = (rgb >> 8) & 0xff;
  final blue = rgb & 0xff;
  return '&H${blue.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${red.toRadixString(16).padLeft(2, '0')}&';
}

String _escapeAss(String text) {
  return text
      .replaceAll('\\', '＼')
      .replaceAll('{', '｛')
      .replaceAll('}', '｝')
      .replaceAll(RegExp(r'[\r\n]+'), '\\N');
}

String overlayToAss(List<CommentOverlay> items) {
  final buffer = StringBuffer();
  buffer.writeln('[Script Info]');
  buffer.writeln('ScriptType: v4.00+');
  buffer.writeln('PlayResX: 1920');
  buffer.writeln('PlayResY: 1080');
  buffer.writeln('WrapStyle: 2');
  buffer.writeln('ScaledBorderAndShadow: yes');
  buffer.writeln();
  buffer.writeln('[V4+ Styles]');
  buffer.writeln(
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
  );
  buffer.writeln(
    'Style: Danmaku,Microsoft YaHei,42,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,1,7,0,0,0,1',
  );
  buffer.writeln();
  buffer.writeln('[Events]');
  buffer.writeln(
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
  );

  final supported = items.where((item) => item.isSupported).toList();
  final laneBusyUntil = <double>[];
  for (var index = 0; index < supported.length; index += 1) {
    final item = supported[index];
    final end = item.time + 4;
    final color = assColor(item.color);
    if (item.mode == 4) {
      buffer.writeln(
        'Dialogue: 0,${_assTime(item.time)},${_assTime(end)},Danmaku,,0,0,0,,'
        '{\\an2\\pos(960,1050)\\c$color}${_escapeAss(item.text)}',
      );
      continue;
    }
    if (item.mode == 5) {
      buffer.writeln(
        'Dialogue: 0,${_assTime(item.time)},${_assTime(end)},Danmaku,,0,0,0,,'
        '{\\an8\\pos(960,30)\\c$color}${_escapeAss(item.text)}',
      );
      continue;
    }
    var lane = 0;
    while (lane < laneBusyUntil.length && laneBusyUntil[lane] > item.time) {
      lane += 1;
    }
    if (lane >= laneBusyUntil.length) {
      laneBusyUntil.add(end);
    } else {
      laneBusyUntil[lane] = end;
    }
    final y = 80 + (lane % 16) * 56;
    buffer.writeln(
      'Dialogue: 0,${_assTime(item.time)},${_assTime(end)},Danmaku,,0,0,0,,'
      '{\\an7\\move(1920,$y,-600,$y,0,4000)\\c$color}${_escapeAss(item.text)}',
    );
  }
  return buffer.toString();
}

String overlayToHtml(
  List<CommentOverlay> items, {
  String? videoFileName,
  String? title,
}) {
  final data = items
      .where((item) => item.isSupported)
      .map(
        (item) => {
          't': item.time,
          'm': item.mode,
          'c': '#${item.color.toRadixString(16).padLeft(6, '0')}',
          'x': item.text,
        },
      )
      .toList();
  final json = jsonEncode(data);
  final safeTitle = const HtmlEscape().convert(title ?? '弹幕回放');
  final videoTag = videoFileName == null || videoFileName.isEmpty
      ? ''
      : '<video id="video" controls preload="metadata" src="${const HtmlEscape().convert(videoFileName)}"></video>';
  final controls = videoFileName == null || videoFileName.isEmpty
      ? '<button id="play">播放弹幕</button><input id="seek" type="range" min="0" max="${items.isEmpty ? 1 : (items.last.time + 5).ceil()}" step="0.1" value="0"><span id="clock">0.0s</span>'
      : '';

  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #101014; color: #eee; font-family: system-ui, -apple-system, "Microsoft YaHei", sans-serif; }
  #stage { position: relative; width: 100%; aspect-ratio: 16/9; overflow: hidden; background: #000; }
  #video { width: 100%; height: 100%; object-fit: contain; display: block; background: #000; }
  .danmaku { position: absolute; white-space: nowrap; font-weight: 600; text-shadow: 1px 1px 2px #000, -1px -1px 2px #000; will-change: transform; pointer-events: none; font-size: clamp(16px, 2.2vw, 34px); }
  @keyframes scroll { from { transform: translateX(100vw); } to { transform: translateX(-110%); } }
  @keyframes stay { from { opacity: 1; } to { opacity: 0; } }
  #controls { display: flex; gap: 12px; align-items: center; padding: 12px 16px; }
  button, input[type=range] { font: inherit; }
  #app { max-width: 1280px; margin: 0 auto; }
  h1 { font-size: 16px; padding: 0 16px; color: #bbb; font-weight: 500; }
</style>
</head>
<body>
<div id="app">
  <h1>$safeTitle</h1>
  <div id="stage">$videoTag</div>
  <div id="controls">$controls</div>
</div>
<script>
const DANMAKU = $json;
const stage = document.getElementById('stage');
const video = document.getElementById('video');
let lastTime = 0;
let virtualTime = 0;
let playing = !video;
let lastFrame = performance.now();
const lanes = [];
function laneFor(time, mode) {
  const count = 14;
  for (let i = 0; i < count; i++) {
    if (!lanes[i] || lanes[i] < time) { lanes[i] = time + 4; return i; }
  }
  return Math.floor(Math.random() * count);
}
function spawn(item) {
  const el = document.createElement('div');
  el.className = 'danmaku';
  el.textContent = item.x;
  el.style.color = item.c;
  const lane = laneFor(item.t, item.m);
  if (item.m === 5) {
    el.style.left = '50%';
    el.style.top = (4 + lane * 6) + '%';
    el.style.transform = 'translateX(-50%)';
    el.style.animation = 'stay 4s linear forwards';
  } else if (item.m === 4) {
    el.style.left = '50%';
    el.style.bottom = (4 + lane * 6) + '%';
    el.style.transform = 'translateX(-50%)';
    el.style.animation = 'stay 4s linear forwards';
  } else {
    el.style.top = (4 + lane * 6) + '%';
    el.style.animation = 'scroll 8s linear forwards';
  }
  stage.appendChild(el);
  setTimeout(() => el.remove(), 8200);
}
function emit(time) {
  for (const item of DANMAKU) {
    if (item.t > lastTime && item.t <= time) spawn(item);
  }
  lastTime = time;
}
function reset(to) { lastTime = to; lanes.length = 0; for (const el of Array.from(document.querySelectorAll('.danmaku'))) el.remove(); }
function tick() {
  let time;
  if (video) { time = video.currentTime || 0; }
  else { const now = performance.now(); if (playing) virtualTime += (now - lastFrame) / 1000; lastFrame = now; time = virtualTime; }
  if (time < lastTime) reset(time);
  emit(time);
  const seek = document.getElementById('seek');
  const clock = document.getElementById('clock');
  if (seek) { seek.value = time; clock.textContent = time.toFixed(1) + 's'; }
  requestAnimationFrame(tick);
}
if (!video) {
  document.getElementById('play').onclick = () => { playing = !playing; lastFrame = performance.now(); };
  document.getElementById('seek').oninput = (event) => { virtualTime = Number(event.target.value); reset(virtualTime); };
}
requestAnimationFrame(tick);
</script>
</body>
</html>
''';
}
