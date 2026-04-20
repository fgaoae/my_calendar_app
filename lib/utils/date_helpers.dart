import 'package:flutter/material.dart';

/// 日期和时间处理工具类
class DateHelper {
  /// 选择日期和时间
  static Future<DateTime?> pickDateThenTime(
    BuildContext context,
    DateTime? initial,
  ) async {
    final base = initial ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return null;
    if (!context.mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// 仅选择日期
  static Future<DateTime?> pickDate(
    BuildContext context,
    DateTime? initial,
  ) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  /// 格式化DateTime为显示字符串
  static String formatDateTime(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) {
      return value.toLocal().toString().substring(0, 19);
    }
    return value.toString();
  }

  /// 格式化DateTime为 YYYY-MM-DD HH:mm
  static String formatYmd(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化DateTime为 YYYY-MM-DD
  static String formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// 解析ISO8601字符串并转为本地时间
  static DateTime? parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value).toLocal();
    } catch (e) {
      return null;
    }
  }

  /// 转换为UTC并返回ISO8601字符串
  static String toUtcIso8601(DateTime dt) {
    return dt.toUtc().toIso8601String();
  }
}
