const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/// e.g. "June 8, 2025"
String formatLongDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

/// e.g. "9:45 AM"
String formatTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
