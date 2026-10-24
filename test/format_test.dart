import 'package:flutter_test/flutter_test.dart';
import 'package:xinji/core/utils/format.dart';

void main() {
  test('formatHours：小时+分钟格式', () {
    expect(formatHours(0), '0分钟');
    expect(formatHours(0.5), '30分钟');
    expect(formatHours(1), '1小时');
    expect(formatHours(2.5), '2小时30分');
    expect(formatHours(3.75), '3小时45分');
    expect(formatHours(7.25), '7小时15分');
    expect(formatHours(8), '8小时');
  });
}
