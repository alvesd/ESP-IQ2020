// Parser for 14-day NVS-persisted ESPHome history strings emitted by iq2020_history
// (e.g. "6h:101.8,102.0,,102.4" or "1d:4.12,5.30").

class HistorySeries {
  final String intervalLabel;
  final int bucketHours;
  final List<double?> values;

  const HistorySeries({
    required this.intervalLabel,
    required this.bucketHours,
    required this.values,
  });

  static const empty = HistorySeries(intervalLabel: '', bucketHours: 6, values: []);

  factory HistorySeries.parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == 'NA' || s == '—') return empty;
    final colon = s.indexOf(':');
    if (colon <= 0) return empty;
    final prefix = s.substring(0, colon).trim();
    final body = s.substring(colon + 1);
    if (body.trim().isEmpty) return empty;

    int hours = 6;
    if (prefix.endsWith('h')) {
      hours = int.tryParse(prefix.substring(0, prefix.length - 1)) ?? 6;
    } else if (prefix.endsWith('d')) {
      hours = (int.tryParse(prefix.substring(0, prefix.length - 1)) ?? 1) * 24;
    }

    final vals = <double?>[];
    for (final token in body.split(',')) {
      final t = token.trim();
      vals.add(t.isEmpty ? null : double.tryParse(t));
    }
    if (vals.every((v) => v == null)) return empty;
    return HistorySeries(intervalLabel: prefix, bucketHours: hours, values: vals);
  }

  List<double> get nonNullValues => [for (final v in values) if (v != null) v];

  bool get isEmpty => nonNullValues.isEmpty;
  bool get isNotEmpty => nonNullValues.isNotEmpty;

  double? get latest {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }

  double? get min {
    final nn = nonNullValues;
    if (nn.isEmpty) return null;
    return nn.reduce((a, b) => a < b ? a : b);
  }

  double? get max {
    final nn = nonNullValues;
    if (nn.isEmpty) return null;
    return nn.reduce((a, b) => a > b ? a : b);
  }

  double? get average {
    final nn = nonNullValues;
    if (nn.isEmpty) return null;
    return nn.reduce((a, b) => a + b) / nn.length;
  }

  String get spanLabel {
    if (values.isEmpty) return '';
    final totalHours = values.length * bucketHours;
    if (totalHours >= 24) {
      final days = (totalHours / 24).round();
      return '${days}d';
    }
    return '${totalHours}h';
  }
}
