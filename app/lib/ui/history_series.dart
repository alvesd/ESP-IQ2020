// Parser for 3-tier NVS-persisted ESPHome history strings emitted by iq2020_history:
//   "6h:101.8,102.0,,102.4"
//   "1d@2026-11-27:4.12,5.30" (or legacy "1d:4.12,5.30")
//   "1mo@2026-11:112.3,145.6" (or "1mo:112.3,145.6")

class HistorySeries {
  final String intervalLabel;
  final int bucketHours;
  final DateTime? endDate;
  final List<double?> values;

  const HistorySeries({
    required this.intervalLabel,
    required this.bucketHours,
    this.endDate,
    required this.values,
  });

  static const empty = HistorySeries(intervalLabel: '', bucketHours: 6, values: []);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  bool get isMonthly => intervalLabel.endsWith('mo');
  bool get isDaily => intervalLabel.endsWith('d');

  factory HistorySeries.parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == 'NA' || s == '—') return empty;
    final colon = s.indexOf(':');
    if (colon <= 0) return empty;
    final rawPrefix = s.substring(0, colon).trim();
    final body = s.substring(colon + 1);
    if (body.trim().isEmpty) return empty;

    String prefix = rawPrefix;
    DateTime? endDate;
    final at = rawPrefix.indexOf('@');
    if (at > 0) {
      prefix = rawPrefix.substring(0, at).trim();
      final dateStr = rawPrefix.substring(at + 1).trim();
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) endDate = DateTime(y, m, d);
      } else if (parts.length == 2) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y != null && m != null) endDate = DateTime(y, m, 1);
      }
    }

    int hours = 6;
    if (prefix.endsWith('mo')) {
      hours = (int.tryParse(prefix.substring(0, prefix.length - 2)) ?? 1) * 24 * 30;
    } else if (prefix.endsWith('d')) {
      hours = (int.tryParse(prefix.substring(0, prefix.length - 1)) ?? 1) * 24;
    } else if (prefix.endsWith('h')) {
      hours = int.tryParse(prefix.substring(0, prefix.length - 1)) ?? 6;
    }

    final vals = <double?>[];
    for (final token in body.split(',')) {
      final t = token.trim();
      vals.add(t.isEmpty ? null : double.tryParse(t));
    }
    if (vals.every((v) => v == null)) return empty;
    return HistorySeries(intervalLabel: prefix, bucketHours: hours, endDate: endDate, values: vals);
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

  double? get sum {
    final nn = nonNullValues;
    if (nn.isEmpty) return null;
    return nn.fold<double>(0.0, (a, b) => a + b);
  }

  /// Trailing [count] buckets (e.g. slicing the last 12 months from a 24-month series).
  HistorySeries lastN(int count) {
    if (count <= 0 || values.length <= count) return this;
    final sliced = values.sublist(values.length - count);
    if (sliced.every((v) => v == null)) return empty;
    return HistorySeries(
      intervalLabel: intervalLabel,
      bucketHours: bucketHours,
      endDate: endDate,
      values: sliced,
    );
  }

  /// For daily series anchored to [endDate], keeps only days falling in the ending calendar month.
  HistorySeries thisMonthOnly() {
    final end = endDate;
    if (!isDaily || end == null || values.isEmpty) return this;
    var firstIdx = values.length;
    for (var i = 0; i < values.length; i++) {
      final d = DateTime(end.year, end.month, end.day - (values.length - 1 - i));
      if (d.year == end.year && d.month == end.month) {
        firstIdx = i;
        break;
      }
    }
    if (firstIdx >= values.length) return empty;
    final sliced = values.sublist(firstIdx);
    if (sliced.every((v) => v == null)) return empty;
    return HistorySeries(
      intervalLabel: intervalLabel,
      bucketHours: bucketHours,
      endDate: end,
      values: sliced,
    );
  }

  /// Formatted month+year string for endDate when monthly (`YYYY-MM`).
  String? get endMonthKey {
    final end = endDate;
    if (end == null) return null;
    return '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}';
  }

  String labelForIndex(int index) {
    if (index < 0 || index >= values.length) return '';
    final offset = values.length - 1 - index;
    final end = endDate;
    if (isMonthly) {
      if (end != null) {
        final totalM = end.year * 12 + (end.month - 1) - offset;
        final m = (totalM % 12 + 12) % 12;
        final y = totalM >= 0 ? totalM ~/ 12 : ((totalM - 11) ~/ 12);
        final mon = _months[m];
        return values.length > 12 ? "$mon '${(y % 100).toString().padLeft(2, '0')}" : mon;
      }
      return offset == 0 ? 'Now' : '-${offset}m';
    }
    if (isDaily) {
      if (end != null) {
        final d = DateTime(end.year, end.month, end.day - offset);
        return '${_months[d.month - 1]} ${d.day}';
      }
      return offset == 0 ? 'Today' : '-${offset}d';
    }
    if (offset == 0) return 'Now';
    final h = offset * bucketHours;
    return h >= 24 ? '-${(h / 24).round()}d' : '-${h}h';
  }

  String get spanLabel {
    if (values.isEmpty) return '';
    if (isMonthly) {
      if (values.length >= 12 && values.length % 12 == 0) {
        return '${values.length ~/ 12}yr';
      }
      return '${values.length}mo';
    }
    if (isDaily) return '${values.length}d';
    final totalHours = values.length * bucketHours;
    if (totalHours >= 24) {
      return '${(totalHours / 24).round()}d';
    }
    return '${totalHours}h';
  }
}
