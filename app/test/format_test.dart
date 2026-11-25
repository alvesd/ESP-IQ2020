import 'package:flutter/painting.dart';
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

  test('temperature colour runs blue (cool) to red-orange (hot)', () {
    expect(tempColor(0), const Color(0xFF3D7BFF));
    expect(tempColor(1), const Color(0xFFFF5A36));
    expect(tempColor(2), const Color(0xFFFF5A36)); // clamped
    final mid = tempColor(0.9);
    expect(mid.r, greaterThan(mid.b)); // warm side of the scale
  });

  test('missing values and unknown units', () {
    expect(formatDuration(double.nan, 's'), '—');
    expect(formatDuration(12, 'W'), '12 W');
  });

  test('saltZone matches the panel zones', () {
    expect(saltZone(double.nan), isNull);
    expect(saltZone(0)!.$1, 'Too low');
    expect(saltZone(23)!.$1, 'Too low');
    expect(saltZone(24)!.$1, 'Low');
    expect(saltZone(35)!.$1, 'Low');
    expect(saltZone(36)!.$1, 'Good');
    expect(saltZone(83)!.$1, 'Good');
    expect(saltZone(84)!.$1, 'High');
    expect(saltZone(96)!.$1, 'Too high');
    expect(saltZone(120)!.$1, 'Too high');
    expect(saltZone(150)!.$1, 'Too high');
  });
}
