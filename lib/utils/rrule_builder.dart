/// RRule（重复规则）构建和解析工具类
class RRuleBuilder {
  /// 映射weekday到RRule的BYDAY值
  static const Map<int, String> _weekdayMap = {
    1: 'MO', // Monday
    2: 'TU', // Tuesday
    3: 'WE', // Wednesday
    4: 'TH', // Thursday
    5: 'FR', // Friday
    6: 'SA', // Saturday
    7: 'SU', // Sunday
  };

  /// 构建RRule字符串
  /// 
  /// [frequency] - 重复频率: DAILY, WEEKLY, MONTHLY, YEARLY
  /// [startDate] - 开始日期（用于确定BYDAY/BYMONTHDAY）
  /// [endDate] - 结束日期（可选，用于设置UNTIL）
  static String build({
    required String frequency,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final parts = <String>['FREQ=$frequency', 'INTERVAL=1'];

    if (frequency == 'WEEKLY') {
      parts.add('BYDAY=${_weekdayMap[startDate.weekday] ?? 'MO'}');
    }

    if (frequency == 'MONTHLY') {
      parts.add('BYMONTHDAY=${startDate.day}');
    }

    if (endDate != null) {
      // 使用floating/local UNTIL来避免timezone问题
      final until = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );
      final untilStr =
          '${until.year.toString().padLeft(4, '0')}'
          '${until.month.toString().padLeft(2, '0')}'
          '${until.day.toString().padLeft(2, '0')}'
          'T${until.hour.toString().padLeft(2, '0')}'
          '${until.minute.toString().padLeft(2, '0')}'
          '${until.second.toString().padLeft(2, '0')}';
      parts.add('UNTIL=$untilStr');
    }

    return parts.join(';');
  }

  /// 解析RRule字符串，返回 (frequency, endDate, byDay)
  static (String frequency, DateTime? endDate, String? byDay)? parse(String rrule) {
    try {
      final parts = rrule.split(';');
      String? freq;
      DateTime? until;
      String? byday;

      for (final part in parts) {
        if (part.startsWith('FREQ=')) {
          freq = part.substring(5);
        } else if (part.startsWith('UNTIL=')) {
          final untilStr = part.substring(6);
          // 解析 YYYYMMDDTHHMMSS 格式
          if (untilStr.length >= 15) {
            final year = int.parse(untilStr.substring(0, 4));
            final month = int.parse(untilStr.substring(4, 6));
            final day = int.parse(untilStr.substring(6, 8));
            until = DateTime(year, month, day);
          }
        } else if (part.startsWith('BYDAY=')) {
          byday = part.substring(6);
        }
      }

      if (freq == null) return null;
      return (freq, until, byday);
    } catch (e) {
      return null;
    }
  }
}
