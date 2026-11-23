import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/ui/spa_screen.dart';

void main() {
  test('runtime seconds show as days and hours', () {
    // Values seen on the real spa.
    expect(formatDuration(159692448, 's'), '1,848d 7h');
    expect(formatDuration(5935530, 's'), '68d 16h');
    expect(formatDuration(0, 's'), '0m');
  });

  test('short durations fall back to hours/minutes', () {
    expect(formatDuration(3 * 3600 + 25 * 60, 's'), '3h 25m');
    expect(formatDuration(42 * 60, 's'), '42m');
  });

  test('hour-based counters convert too', () {
    expect(formatDuration(9271, 'h'), '386d 7h');
  });

  test('missing values and unknown units', () {
    expect(formatDuration(double.nan, 's'), '—');
    expect(formatDuration(12, 'W'), '12 W');
  });
}
