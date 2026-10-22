import 'package:intl/intl.dart';

String formatBytes(num? value) {
  if (value == null || value < 0) {
    return '--';
  }
  if (value < 1024) {
    return '${value.round()} B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var amount = value / 1024;
  var index = 0;
  while (amount >= 1024 && index < units.length - 1) {
    amount /= 1024;
    index += 1;
  }
  final digits = amount >= 100 ? 0 : (amount >= 10 ? 1 : 2);
  return '${amount.toStringAsFixed(digits)} ${units[index]}';
}

String formatSpeed(num? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) {
    return '--';
  }
  return '${formatBytes(bytesPerSecond)}/s';
}

String formatDuration(Duration duration) {
  if (duration.inSeconds <= 0) {
    return '--';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatDurationMs(int? milliseconds) {
  if (milliseconds == null || milliseconds <= 0) {
    return '--';
  }
  return formatDuration(Duration(milliseconds: milliseconds));
}

String formatTimestamp(DateTime? value) {
  if (value == null) {
    return '--';
  }
  return DateFormat('yyyy-MM-dd HH:mm').format(value);
}

String formatDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return DateFormat('yyyy-MM-dd').format(value);
}
