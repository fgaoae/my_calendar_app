import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../constants.dart';
import '../theme/airy_theme.dart';
import '../utils/date_helpers.dart';
import '../utils/rrule_builder.dart';
import '../widgets/airy_components.dart';

// ============ 日历视图 ============
class CalendarViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  final Stream<List<Map<String, dynamic>>> dbStream;
  final ValueListenable<int> syncTick;
  final VoidCallback requestSync;

  const CalendarViewWidget({
    super.key,
    required this.eventStream,
    required this.dbStream,
    required this.syncTick,
    required this.requestSync,
  });

  @override
  State<CalendarViewWidget> createState() => _CalendarViewWidgetState();
}

class _CalendarViewWidgetState extends State<CalendarViewWidget> {
  late final CalendarEventDataSource _dataSource;
  late final StreamSubscription<List<Map<String, dynamic>>> _eventSub;
  late final StreamSubscription<List<Map<String, dynamic>>> _dbSub;
  final CalendarController _calendarController = CalendarController();
  final GlobalKey _calendarKey = GlobalKey();

  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _allDbs = [];
  bool _loading = true;
  bool _isRefreshing = false;
  int _refreshTasks = 0;

  Timer? _syncDebounce;

  bool _calendarHoveringDrag = false;
  final Duration _defaultDropDuration = const Duration(hours: 1);

  // 记录拖拽时的全局指针位置，优先以日历目标区的最新坐标为准。
  Offset? _lastGlobalDragPointerInTarget;
  Offset? _lastGlobalDragPointerAny;
  late final VoidCallback _syncListener;

  @override
  void initState() {
    super.initState();

    _calendarController.view = CalendarView.week;
    _calendarController.displayDate = DateTime.now();
    _dataSource = CalendarEventDataSource(const <Appointment>[]);

    _eventSub = widget.eventStream.listen((data) {
      _allEvents = List<Map<String, dynamic>>.from(data);
      _rebuildAppointments();
    });

    _dbSub = widget.dbStream.listen((data) {
      _allDbs = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      setState(() => _loading = false);
      _rebuildAppointments();
    });

    _syncListener = () {
      if (!mounted) return;
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        unawaited(_hardRefreshEvents());
      });
    };
    widget.syncTick.addListener(_syncListener);

    _hardRefreshEvents();
    _hardRefreshDatabases();
  }

  @override
  void dispose() {
    widget.syncTick.removeListener(_syncListener);
    _syncDebounce?.cancel();
    _eventSub.cancel();
    _dbSub.cancel();
    _calendarController.dispose();
    super.dispose();
  }

  void _startRefresh() {
    _refreshTasks += 1;
    if (!_isRefreshing && mounted) {
      setState(() => _isRefreshing = true);
    }
  }

  void _endRefresh() {
    if (_refreshTasks > 0) {
      _refreshTasks -= 1;
    }
    if (_refreshTasks == 0 && _isRefreshing && mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _refreshAllData() async {
    await Future.wait([
      _hardRefreshEvents(),
      _hardRefreshDatabases(),
    ]);
  }

  Future<void> _hardRefreshEvents() async {
    _startRefresh();
    try {
      final fresh = await Supabase.instance.client
          .from('events')
          .select()
          .order('sort_order');
      _allEvents = List<Map<String, dynamic>>.from(fresh);
      _rebuildAppointments();
    } finally {
      _endRefresh();
    }
  }

  Future<void> _hardRefreshDatabases() async {
    _startRefresh();
    try {
      final fresh = await Supabase.instance.client
          .from('databases')
          .select()
          .order('created_at');
      _allDbs = List<Map<String, dynamic>>.from(fresh);
      if (!mounted) return;
      setState(() => _loading = false);
      _rebuildAppointments();
    } finally {
      _endRefresh();
    }
  }

  Widget _buildAnimatedDialog(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: AiryTheme.medium,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final opacity = ((value - 0.94) / 0.06).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: value, child: child),
        );
      },
    );
  }

  String? get _hiddenDbId {
    for (final db in _allDbs) {
      if (db['name']?.toString() == kHiddenDatabaseName) {
        return db['id']?.toString();
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleEvents {
    return _allEvents;
  }

  List<Map<String, dynamic>> get _visibleDbs {
    return _allDbs
        .where((d) => d['name']?.toString() != kHiddenDatabaseName)
        .toList();
  }

  List<Map<String, dynamic>> _eventsByDb(String dbId) {
    return _allEvents
        .where((e) => e['database_id']?.toString() == dbId)
        .toList();
  }

  String _pad2(int value) => value.toString().padLeft(2, '0');

  String _formatYmd(DateTime dt) {
    return '${dt.year}年${_pad2(dt.month)}月${_pad2(dt.day)}日';
  }

  String _formatHm(DateTime dt) {
    return '${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  }

  DateTime _startOfWeek(DateTime dt) {
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: diff));
  }

  String _formatTopBarDateLabel() {
    final date = _calendarController.displayDate ?? DateTime.now();
    final view = _calendarController.view ?? CalendarView.week;

    switch (view) {
      case CalendarView.month:
        return '${date.year}年${_pad2(date.month)}月';
      case CalendarView.day:
        return _formatYmd(date);
      case CalendarView.timelineWeek:
      case CalendarView.week:
        final start = _startOfWeek(date);
        final end = start.add(const Duration(days: 6));
        return '${_formatYmd(start)} - ${_formatYmd(end)}';
      default:
        return _formatYmd(date);
    }
  }

  Widget _buildAppointmentCard(
    BuildContext context,
    CalendarAppointmentDetails details,
  ) {
    final dynamic first = details.appointments.isNotEmpty
        ? details.appointments.first
        : null;
    if (first is! Appointment) {
      return const SizedBox.shrink();
    }

    final view = _calendarController.view ?? CalendarView.week;
    final compact =
        view == CalendarView.month ||
        details.bounds.height < 34 ||
        details.bounds.width < 100;
    final appId = first.id?.toString() ??
        '${first.startTime.microsecondsSinceEpoch}-${first.subject}';

    return _AiryAppointmentCard(
      key: ValueKey('calendar-app-$appId'),
      subject: first.subject,
      timeText: '${_formatHm(first.startTime)}-${_formatHm(first.endTime)}',
      color: first.color,
      compact: compact,
      recurring: (first.recurrenceRule ?? '').toString().isNotEmpty,
    );
  }

  Color _databaseColor(String? dbId) {
    if (dbId == null || dbId.isEmpty) return AiryPalette.accent;
    final hiddenId = _hiddenDbId;
    if (hiddenId != null && hiddenId == dbId) {
      return AiryPalette.textMuted;
    }
    return AiryPalette.databaseAccentForId(dbId);
  }

  void _patchLocalEventById(String id, Map<String, dynamic> updates) {
    final idx = _allEvents.indexWhere(
      (e) => e['id'] != null && e['id'].toString() == id,
    );
    if (idx < 0) return;
    final next = List<Map<String, dynamic>>.from(_allEvents);
    final merged = Map<String, dynamic>.from(next[idx]);
    merged.addAll(updates);
    next[idx] = merged;
    _allEvents = next;
    _rebuildAppointments();
  }

  void _removeLocalEventById(String id) {
    _allEvents = _allEvents
        .where((e) => e['id'] == null || e['id'].toString() != id)
        .toList();
    _rebuildAppointments();
  }

  void _rebuildAppointments() {
    final List<Appointment> list = [];
    for (final item in _visibleEvents) {
      if (item['start_time'] == null) continue;
      try {
        final start = DateTime.parse(item['start_time'].toString()).toLocal();
        final end = item['end_time'] != null
            ? DateTime.parse(item['end_time'].toString()).toLocal()
            : start.add(const Duration(hours: 1));

        final props = Map<String, dynamic>.from(item['properties'] ?? {});
        final rrule = item['is_recurring'] == true
            ? props['_sys_rrule']?.toString()
            : null;

        final List<DateTime> exDates = [];
        final rawEx = props['_sys_exdates'];
        if (rawEx is List) {
          for (final v in rawEx) {
            final s = v?.toString();
            if (s == null || s.isEmpty) continue;
            final dt = DateTime.tryParse(s);
            if (dt == null) continue;
            exDates.add(dt.toLocal());
          }
        }

        final dbColor = _databaseColor(item['database_id']?.toString());

        list.add(
          Appointment(
            id: item['id'],
            startTime: start,
            endTime: end,
            subject: (item['title'] ?? '未命名').toString(),
            notes: (item['description'] ?? '').toString(),
            color: dbColor,
            recurrenceRule: rrule,
            recurrenceExceptionDates: exDates.isEmpty ? null : exDates,
          ),
        );
      } catch (_) {}
    }
    _dataSource.updateAppointments(list);
    if (!mounted) return;
    setState(() {});
  }

  Future<String> _ensureHiddenDatabaseId() async {
    final existing = _hiddenDbId;
    if (existing != null && existing.isNotEmpty) return existing;

    final inserted = await Supabase.instance.client
        .from('databases')
        .insert({
          'name': kHiddenDatabaseName,
          'schema': [],
          'property_types': {},
          'tag_options': {},
        })
        .select()
        .single();

    final id = inserted['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Failed to create hidden database');
    }

    await _hardRefreshDatabases();
    return id;
  }

  Future<void> _addHiddenEventAt(DateTime date) async {
    final hiddenDbId = await _ensureHiddenDatabaseId();
    final start = _normalizeDropTime(date);
    final end = start.add(_defaultDropDuration);

    final inserted = await Supabase.instance.client.from('events').insert({
      'database_id': hiddenDbId,
      'title': '未命名',
      'description': '',
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'is_recurring': false,
      'properties': {},
      'sort_order': _allEvents.length + 1,
    }).select().single();

    _allEvents = [..._allEvents, Map<String, dynamic>.from(inserted)];
    _rebuildAppointments();
    widget.requestSync();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到隐藏数据库')),
    );
  }

  DateTime _normalizeDropTime(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final normalized = DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
    if (_calendarController.view == CalendarView.month) {
      return DateTime(local.year, local.month, local.day, 9, 0);
    }
    return normalized;
  }

  DateTime? _resolveDropTimeFromOffset(Offset globalOffset) {
    try {
      final ctx = _calendarKey.currentContext;
      if (ctx == null) return null;

      final rb = ctx.findRenderObject();
      if (rb is! RenderBox) return null;

      final localOffset = rb.globalToLocal(globalOffset);

      final callback = _calendarController.getCalendarDetailsAtOffset;
      if (callback == null) return null;

      final CalendarDetails? details = callback(localOffset);
      final DateTime? dt = details?.date;
      if (dt == null) return null;

      return _normalizeDropTime(dt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _scheduleExternalDropByOffset(
    Map<String, dynamic> eventRow,
    Offset globalOffset,
  ) async {
    final resolved = _resolveDropTimeFromOffset(globalOffset);
    final start =
        resolved ??
        (() {
          final d = _calendarController.displayDate ?? DateTime.now();
          return DateTime(d.year, d.month, d.day, 9, 0);
        })();

    final oldStart = eventRow['start_time'] != null
        ? DateTime.tryParse(eventRow['start_time'].toString())?.toLocal()
        : null;
    final oldEnd = eventRow['end_time'] != null
        ? DateTime.tryParse(eventRow['end_time'].toString())?.toLocal()
        : null;

    Duration duration = _defaultDropDuration;
    if (oldStart != null && oldEnd != null && oldEnd.isAfter(oldStart)) {
      duration = oldEnd.difference(oldStart);
    }

    final end = start.add(duration);

    final id = eventRow['id']?.toString();
    if (id == null || id.isEmpty) return;
    _patchLocalEventById(id, {
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
    });

    try {
      await Supabase.instance.client
          .from('events')
          .update({
            'start_time': start.toUtc().toIso8601String(),
            'end_time': end.toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (_) {
      unawaited(_hardRefreshEvents());
    }
  }

  Future<void> _moveAppointment(Appointment app, DateTime newStart) async {
    final dynamic id = app.id;
    if (id == null) return;

    final duration = app.endTime.difference(app.startTime);
    final newEnd = newStart.add(duration);

    _patchLocalEventById(id.toString(), {
      'start_time': newStart.toUtc().toIso8601String(),
      'end_time': newEnd.toUtc().toIso8601String(),
    });

    try {
      await Supabase.instance.client
          .from('events')
          .update({
            'start_time': newStart.toUtc().toIso8601String(),
            'end_time': newEnd.toUtc().toIso8601String(),
          })
          .eq('id', id.toString());
    } catch (_) {
      unawaited(_hardRefreshEvents());
    }
    widget.requestSync();
  }

  Future<void> _resizeAppointment(
    Appointment app,
    DateTime newStart,
    DateTime newEnd,
  ) async {
    final dynamic id = app.id;
    if (id == null) return;

    _patchLocalEventById(id.toString(), {
      'start_time': newStart.toUtc().toIso8601String(),
      'end_time': newEnd.toUtc().toIso8601String(),
    });

    try {
      await Supabase.instance.client
          .from('events')
          .update({
            'start_time': newStart.toUtc().toIso8601String(),
            'end_time': newEnd.toUtc().toIso8601String(),
          })
          .eq('id', id.toString());
    } catch (_) {
      unawaited(_hardRefreshEvents());
    }
    widget.requestSync();
  }

  Future<void> _editEventDialog(
    Map<String, dynamic> row, {
    DateTime? occurrenceStart,
  }) async {
    // Ensure we have the latest database schema
    await _hardRefreshDatabases();
    if (!mounted) return;

    final titleCtrl = TextEditingController(
      text: row['title']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: row['description']?.toString() ?? '',
    );

    final String? dbId = row['database_id']?.toString();
    final Map<String, dynamic>? dbRow = (dbId == null)
        ? null
        : (() {
            final found = _allDbs.firstWhere(
              (d) => d['id']?.toString() == dbId,
              orElse: () => <String, dynamic>{},
            );
            return found.isEmpty ? null : found;
          })();

    final schema = List<String>.from(dbRow?['schema'] ?? const <String>[]);
    final propertyTypes = Map<String, dynamic>.from(
      dbRow?['property_types'] ?? const <String, dynamic>{},
    );
    final tagOptions = Map<String, dynamic>.from(
      dbRow?['tag_options'] ?? const <String, dynamic>{},
    );

    final props = Map<String, dynamic>.from(row['properties'] ?? {});

    DateTime? start = row['start_time'] != null
        ? DateTime.tryParse(row['start_time'].toString())?.toLocal()
        : null;
    DateTime? end = row['end_time'] != null
        ? DateTime.tryParse(row['end_time'].toString())?.toLocal()
        : null;

    String reminder = props['_sys_reminder']?.toString() ?? 'NONE';

    String freq = 'NONE';
    DateTime? repeatStartDate = start ?? DateTime.now();
    DateTime? repeatEndDate;

    final oldR = props['_sys_rrule']?.toString() ?? '';
    if (oldR.contains('FREQ=DAILY')) freq = 'DAILY';
    if (oldR.contains('FREQ=WEEKLY')) freq = 'WEEKLY';
    if (oldR.contains('FREQ=MONTHLY')) freq = 'MONTHLY';

    if (props['_sys_repeat_start'] != null) {
      repeatStartDate =
          DateTime.tryParse(props['_sys_repeat_start'].toString())?.toLocal() ??
          repeatStartDate;
    }
    if (props['_sys_repeat_end'] != null) {
      repeatEndDate = DateTime.tryParse(
        props['_sys_repeat_end'].toString(),
      )?.toLocal();
    }

    final textControllers = <String, TextEditingController>{};
    final checkboxValues = <String, bool>{};
    final tagSelected = <String, String>{};

    for (final key in schema) {
      final type = propertyTypes[key]?.toString() ?? 'text';
      if (type == 'checkbox') {
        checkboxValues[key] = props[key] == true;
      } else if (type == 'tag') {
        tagSelected[key] = props[key]?.toString() ?? '';
      } else {
        textControllers[key] = TextEditingController(
          text: props[key]?.toString() ?? '',
        );
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => _buildAnimatedDialog(
          AlertDialog(
          title: const Text('编辑日程'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: '描述'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final dt = await DateHelper.pickDateThenTime(dialogContext, start);
                      if (dt == null) return;
                      setD(() {
                        start = dt;
                        if (end != null &&
                            start != null &&
                            end!.isBefore(start!)) {
                          end = null;
                        }
                      });
                    },
                    child: Text(
                      '开始时间: ${start == null ? '未设置' : start!.toString().substring(0, 16)}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final base = end ?? start ?? DateTime.now();
                      final dt = await DateHelper.pickDateThenTime(dialogContext, base);
                      if (dt == null) return;
                      if (!dialogContext.mounted) return;
                      if (start != null && dt.isBefore(start!)) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('结束时间不能早于开始时间')),
                        );
                        return;
                      }
                      setD(() => end = dt);
                    },
                    child: Text(
                      '结束时间: ${end == null ? '未设置' : end!.toString().substring(0, 16)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: reminder,
                    decoration: const InputDecoration(labelText: '提醒'),
                    items: const [
                      DropdownMenuItem(value: 'NONE', child: Text('不提醒')),
                      DropdownMenuItem(value: '5MIN', child: Text('提前5分钟')),
                      DropdownMenuItem(value: '15MIN', child: Text('提前15分钟')),
                      DropdownMenuItem(value: '1HOUR', child: Text('提前1小时')),
                    ],
                    onChanged: (v) => setD(() => reminder = v ?? 'NONE'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: freq,
                    decoration: const InputDecoration(labelText: '重复'),
                    items: const [
                      DropdownMenuItem(value: 'NONE', child: Text('不重复')),
                      DropdownMenuItem(value: 'DAILY', child: Text('每天')),
                      DropdownMenuItem(value: 'WEEKLY', child: Text('每周')),
                      DropdownMenuItem(value: 'MONTHLY', child: Text('每月')),
                    ],
                    onChanged: (v) {
                      setD(() {
                        freq = v ?? 'NONE';
                        if (freq == 'NONE') {
                          repeatEndDate = null;
                        }
                      });
                    },
                  ),
                  if (freq != 'NONE') ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final d = await DateHelper.pickDate(dialogContext, repeatStartDate);
                        if (d == null) return;
                        setD(() => repeatStartDate = d);
                      },
                      child: Text(
                        '重复开始日期: ${repeatStartDate == null ? '未设置' : DateHelper.formatDate(repeatStartDate!)}',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final d = await DateHelper.pickDate(
                          dialogContext,
                          repeatEndDate ?? repeatStartDate,
                        );
                        if (d == null) return;
                        setD(() => repeatEndDate = d);
                      },
                      child: Text(
                        '重复截止日期: ${repeatEndDate == null ? '永久' : DateHelper.formatDate(repeatEndDate!)}',
                      ),
                    ),
                  ],
                  if (schema.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '属性',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...schema.map((key) {
                      final type = propertyTypes[key]?.toString() ?? 'text';
                      if (type == 'checkbox') {
                        final current = checkboxValues[key] ?? false;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(key),
                          value: current,
                          onChanged: (v) => setD(() {
                            checkboxValues[key] = v ?? false;
                          }),
                        );
                      }

                      if (type == 'tag') {
                        final options = List<String>.from(
                          tagOptions[key] ?? const <String>[],
                        );
                        final selected = tagSelected[key] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (options.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '暂无标签选项',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ...options.map((tag) {
                                        final isSelected = selected == tag;
                                        return InkWell(
                                          onTap: () => setD(() {
                                            tagSelected[key] = tag;
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AiryPalette.accent
                                                      .withValues(alpha: 0.2)
                                                  : Colors.transparent,
                                              border: Border.all(
                                                color: isSelected
                                                    ? AiryPalette.accent
                                                    : Colors.grey.shade300,
                                                width: isSelected ? 2 : 1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  tag,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    color: isSelected
                                                        ? AiryPalette.accent
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                if (isSelected) ...[
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.check,
                                                    size: 14,
                                                    color: AiryPalette.accent,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                      InkWell(
                                        onTap: () => setD(() {
                                          tagSelected[key] = '';
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected.isEmpty
                                                ? Colors.grey.withValues(
                                                    alpha: 0.2,
                                                  )
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: selected.isEmpty
                                                  ? Colors.grey
                                                  : Colors.grey.shade300,
                                              width: selected.isEmpty ? 2 : 1,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '不设置',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: selected.isEmpty
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: selected.isEmpty
                                                      ? Colors.grey
                                                      : Colors.black87,
                                                ),
                                              ),
                                              if (selected.isEmpty) ...[
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.check,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      final c = textControllers[key]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: c,
                          decoration: InputDecoration(labelText: key),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final id = row['id']?.toString();
                if (id == null || id.isEmpty) return;
                final hasRecurrence =
                    (row['is_recurring'] == true) &&
                    (props['_sys_rrule']?.toString().isNotEmpty ?? false);

                if (hasRecurrence && occurrenceStart != null) {
                  final choice = await showDialog<String>(
                    context: dialogContext,
                    builder: (c) => _buildAnimatedDialog(
                      AlertDialog(
                        title: const Text('删除重复事件'),
                        content: const Text('要删除"所有重复"还是"仅本次"？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, 'ONE'),
                            child: const Text('仅本次'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AiryPalette.danger,
                            ),
                            onPressed: () => Navigator.pop(c, 'ALL'),
                            child: const Text('删除所有'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (choice == null) return;

                  if (choice == 'ONE') {
                    final updatedProps = Map<String, dynamic>.from(props);
                    final List<dynamic> ex =
                        (updatedProps['_sys_exdates'] is List)
                            ? List<dynamic>.from(updatedProps['_sys_exdates'])
                            : <dynamic>[];

                    final o = occurrenceStart;
                    final exLocal = DateTime(
                      o.year,
                      o.month,
                      o.day,
                      o.hour,
                      o.minute,
                    );
                    final exIso = exLocal.toUtc().toIso8601String();
                    if (!ex.contains(exIso)) ex.add(exIso);
                    updatedProps['_sys_exdates'] = ex;

                    await Supabase.instance.client
                        .from('events')
                        .update({'properties': updatedProps})
                        .eq('id', id);

                      if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                      if (!mounted) return;
                    _patchLocalEventById(id, {'properties': updatedProps});
                    widget.requestSync();
                    return;
                  }
                }

                await Supabase.instance.client
                    .from('events')
                    .delete()
                    .eq('id', id);
                  if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                  if (!mounted) return;
                _removeLocalEventById(id);
                widget.requestSync();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (start != null && end != null && end!.isBefore(start!)) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
                  return;
                }

                final updatedProps = Map<String, dynamic>.from(props);

                if (reminder == 'NONE') {
                  updatedProps.remove('_sys_reminder');
                } else {
                  updatedProps['_sys_reminder'] = reminder;
                }

                bool isRecurring = false;
                if (freq == 'NONE') {
                  updatedProps.remove('_sys_rrule');
                  updatedProps.remove('_sys_repeat_start');
                  updatedProps.remove('_sys_repeat_end');
                  updatedProps.remove('_sys_exdates');
                } else {
                  isRecurring = true;
                  final base = start ?? DateTime.now();
                  final pickedDate = repeatStartDate ?? base;
                  final effectiveStart = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    base.hour,
                    base.minute,
                  );

                  final duration =
                      (start != null && end != null && end!.isAfter(start!))
                          ? end!.difference(start!)
                          : _defaultDropDuration;

                  start = effectiveStart;
                  end ??= effectiveStart.add(duration);

                  updatedProps['_sys_rrule'] = RRuleBuilder.build(
                    frequency: freq,
                    startDate: effectiveStart,
                    endDate: repeatEndDate,
                  );
                  updatedProps['_sys_repeat_start'] = DateHelper.formatDate(effectiveStart);
                  if (repeatEndDate != null) {
                    updatedProps['_sys_repeat_end'] = DateHelper.formatDate(repeatEndDate!);
                  } else {
                    updatedProps.remove('_sys_repeat_end');
                  }
                }

                for (final key in schema) {
                  final type = propertyTypes[key]?.toString() ?? 'text';

                  if (type == 'checkbox') {
                    updatedProps[key] = checkboxValues[key] ?? false;
                    continue;
                  }

                  if (type == 'tag') {
                    String selected = tagSelected[key]?.trim() ?? '';

                    if (selected.isEmpty) {
                      updatedProps.remove(key);
                    } else {
                      updatedProps[key] = selected;
                    }
                    continue;
                  }

                  final v = textControllers[key]?.text.trim() ?? '';
                  if (v.isEmpty) {
                    updatedProps.remove(key);
                  } else {
                    updatedProps[key] = v;
                  }
                }

                final id = row['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _patchLocalEventById(id, {
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'start_time': start?.toUtc().toIso8601String(),
                    'end_time': end?.toUtc().toIso8601String(),
                    'is_recurring': isRecurring,
                    'properties': updatedProps,
                  });
                }

                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({
                        'title': titleCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'start_time': start?.toUtc().toIso8601String(),
                        'end_time': end?.toUtc().toIso8601String(),
                        'is_recurring': isRecurring,
                        'properties': updatedProps,
                      })
                      .eq('id', row['id']);
                } catch (_) {
                  if (id != null && id.isNotEmpty) {
                    await _hardRefreshEvents();
                  }
                }

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
        ),
      ),
    );

    titleCtrl.dispose();
    descCtrl.dispose();
    for (final c in textControllers.values) {
      c.dispose();
    }
  }

  Widget _buildDragHandle(Map<String, dynamic> e) {
    final title = e['title']?.toString() ?? '未命名';
    final dbColor = _databaseColor(e['database_id']?.toString());
    return Draggable<Map<String, dynamic>>(
      data: e,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                dbColor,
                dbColor.withValues(alpha: 0.78),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: dbColor.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
      onDragStarted: () {
        if (!mounted) return;
        setState(() {
          _calendarHoveringDrag = true;
          _lastGlobalDragPointerInTarget = null;
          _lastGlobalDragPointerAny = null;
        });
      },
      onDragUpdate: (details) {
        _lastGlobalDragPointerAny = details.globalPosition;
      },
      onDragEnd: (_) {
        if (!mounted) return;
        setState(() => _calendarHoveringDrag = false);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.drag_indicator, size: 18, color: dbColor),
      ),
    );
  }

  Widget _buildLeftDatabaseWithData() {
    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: AiryPanel(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('数据库事件', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: _visibleDbs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final db = entry.value;
                    final dbId = db['id'].toString();
                    final dbName = db['name']?.toString() ?? '未命名数据库';
                    final dbColor = _databaseColor(dbId);
                    final rows = _eventsByDb(dbId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AiryPanel(
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            collapsedShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                            iconColor: dbColor,
                            collapsedIconColor: dbColor.withValues(alpha: 0.75),
                            title: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dbColor,
                                    boxShadow: [
                                      BoxShadow(
                                        color: dbColor.withValues(alpha: 0.34),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    dbName,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: AiryStatusPill(text: '${rows.length} 条', color: dbColor),
                            ),
                            children: rows.asMap().entries.map((rowEntry) {
                              final rowIndex = rowEntry.key;
                              final e = rowEntry.value;
                              final title = e['title']?.toString() ?? '未命名';
                              final rawStart = e['start_time']?.toString();
                              final parsed = rawStart == null
                                  ? null
                                  : DateTime.tryParse(rawStart)?.toLocal();
                              final sub = parsed == null
                                  ? '未排期'
                                  : parsed.toString().substring(0, 16);

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: AiryPanel(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 3,
                                        height: 28,
                                        margin: const EdgeInsets.only(left: 4, right: 8),
                                        decoration: BoxDecoration(
                                          color: dbColor.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListTile(
                                          dense: true,
                                          title: Text(
                                            title,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodyLarge,
                                          ),
                                          subtitle: Text(sub),
                                          onTap: () => _editEventDialog(e),
                                        ),
                                      ),
                                      _buildDragHandle(e),
                                    ],
                                  ),
                                )
                                    .animate(delay: (40 + (rowIndex % 10) * 18).ms)
                                    .fadeIn(duration: 260.ms, curve: Curves.easeOutCubic)
                                    .slideY(begin: 0.05, end: 0, duration: 260.ms),
                              );
                            }).toList(),
                          ),
                        ),
                      )
                          .animate(delay: (80 + index * 35).ms)
                          .fadeIn(duration: 360.ms, curve: Curves.easeOutCubic)
                          .slideX(begin: -0.03, end: 0, duration: 360.ms),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final dateLabel = _formatTopBarDateLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: AiryPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final d = _calendarController.displayDate ?? DateTime.now();
                _calendarController.displayDate =
                    _calendarController.view == CalendarView.month
                    ? DateTime(d.year, d.month - 1, d.day)
                    : d.subtract(const Duration(days: 7));
                setState(() {});
              },
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.today),
              onPressed: () {
                _calendarController.displayDate = DateTime.now();
                setState(() {});
              },
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final d = _calendarController.displayDate ?? DateTime.now();
                _calendarController.displayDate =
                    _calendarController.view == CalendarView.month
                    ? DateTime(d.year, d.month + 1, d.day)
                    : d.add(const Duration(days: 7));
                setState(() {});
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: AiryTheme.quick,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  dateLabel,
                  key: ValueKey<String>(dateLabel),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            DropdownButton<CalendarView>(
              value: _calendarController.view,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              items: const [
                DropdownMenuItem(value: CalendarView.month, child: Text('月')),
                DropdownMenuItem(value: CalendarView.week, child: Text('周')),
                DropdownMenuItem(value: CalendarView.day, child: Text('日')),
                DropdownMenuItem(
                  value: CalendarView.timelineWeek,
                  child: Text('时间线'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _calendarController.view = v);
              },
            ),
          ],
        ),
      ).animate().fadeIn(duration: 360.ms).slideY(begin: -0.08, end: 0, duration: 360.ms),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: AiryBackground(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          AirySyncStatus(
            isSyncing: _isRefreshing,
            keyPrefix: 'calendar',
          ),
          AirySyncButton(
            isSyncing: _isRefreshing,
            keyPrefix: 'calendar',
            onPressed: () {
              unawaited(_refreshAllData());
            },
          ),
        ],
      ),
      body: AiryBackground(
        child: Column(
          children: [
            _buildTopBar(),
            AnimatedContainer(
              duration: AiryTheme.quick,
              curve: Curves.easeOutCubic,
              height: _isRefreshing ? 3 : 0,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  backgroundColor: AiryPalette.accentSoft,
                  color: AiryPalette.accent,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _buildLeftDatabaseWithData(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                      child: AiryPanel(
                        padding: EdgeInsets.zero,
                        child: DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (details) {
                      final ok = true;
                      if (ok) setState(() => _calendarHoveringDrag = true);
                      return ok;
                    },
                    onMove: (details) {
                      _lastGlobalDragPointerInTarget = details.offset;
                      if (!_calendarHoveringDrag && mounted) {
                        setState(() => _calendarHoveringDrag = true);
                      }
                    },
                    onLeave: (_) {
                      if (!mounted) return;
                      setState(() => _calendarHoveringDrag = false);
                      _lastGlobalDragPointerInTarget = null;
                    },
                    onAcceptWithDetails: (details) async {
                      setState(() => _calendarHoveringDrag = false);

                      final primary = _lastGlobalDragPointerInTarget;
                      final secondary = details.offset;
                      final tertiary = _lastGlobalDragPointerAny;

                      final primaryTime = primary == null
                          ? null
                          : _resolveDropTimeFromOffset(primary);
                      final secondaryTime = _resolveDropTimeFromOffset(
                        secondary,
                      );
                      final tertiaryTime = tertiary == null
                          ? null
                          : _resolveDropTimeFromOffset(tertiary);

                      Offset chosen = secondary;
                      if (primary != null && primaryTime != null) {
                        chosen = primary;
                      } else if (tertiary != null && tertiaryTime != null) {
                        chosen = tertiary;
                      }

                      if (kDebugMode) {
                        debugPrint(
                          '[external-drop] primary(inTarget)=$primary -> $primaryTime; '
                          'secondary(accept)=$secondary -> $secondaryTime; '
                          'tertiary(any)=$tertiary -> $tertiaryTime; '
                          'chosen=$chosen',
                        );
                        if (primaryTime != null ||
                            secondaryTime != null ||
                            tertiaryTime != null) {
                          debugPrint(
                            '[external-drop] primary.isUtc=${primaryTime?.isUtc}; '
                            'secondary.isUtc=${secondaryTime?.isUtc}; '
                            'tertiary.isUtc=${tertiaryTime?.isUtc}',
                          );
                        }
                      }

                      await _scheduleExternalDropByOffset(details.data, chosen);

                      _lastGlobalDragPointerInTarget = null;
                      _lastGlobalDragPointerAny = null;
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Stack(
                        children: [
                          SfCalendar(
                            key: _calendarKey,
                            controller: _calendarController,
                            dataSource: _dataSource,
                            headerHeight: 0,
                            appointmentBuilder: _buildAppointmentCard,
                            allowDragAndDrop: true,
                            allowAppointmentResize: true,
                            onLongPress: (details) async {
                              final date = details.date;
                              final apps = details.appointments;
                              if (date == null) return;
                              if (apps != null && apps.isNotEmpty) return;
                              await _addHiddenEventAt(date);
                            },
                            onTap: (details) {
                              if (details.appointments != null &&
                                  details.appointments!.isNotEmpty) {
                                final app = details.appointments!.first;
                                if (app is Appointment) {
                                  final dynamic appointmentId = app.id;
                                  if (appointmentId == null) return;
                                  final raw = _visibleEvents.where((x) {
                                    final eventId = x['id'];
                                    return eventId != null &&
                                        eventId.toString() ==
                                            appointmentId.toString();
                                  }).toList();
                                  if (raw.isNotEmpty) {
                                    _editEventDialog(
                                      raw.first,
                                      occurrenceStart: app.startTime,
                                    );
                                  }
                                }
                              }
                            },
                            onDragEnd:
                                (AppointmentDragEndDetails details) async {
                                  final app = details.appointment;
                                  final drop = details.droppingTime;
                                  if (app is Appointment && drop != null) {
                                    await _moveAppointment(app, drop);
                                  }
                                },
                            onAppointmentResizeEnd:
                                (AppointmentResizeEndDetails details) async {
                                  final app = details.appointment;
                                  if (app is Appointment &&
                                      details.startTime != null &&
                                      details.endTime != null) {
                                    await _resizeAppointment(
                                      app,
                                      details.startTime!,
                                      details.endTime!,
                                    );
                                  }
                                },
                          ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: _calendarHoveringDrag ? 1 : 0,
                                  duration: AiryTheme.quick,
                                  curve: Curves.easeOutCubic,
                                  child: Container(
                                    color: AiryPalette.accent.withValues(alpha: 0.08),
                                    alignment: Alignment.topCenter,
                                    padding: const EdgeInsets.only(top: 12),
                                    child: AnimatedSlide(
                                      offset: _calendarHoveringDrag
                                          ? Offset.zero
                                          : const Offset(0, -0.15),
                                      duration: AiryTheme.quick,
                                      curve: Curves.easeOutCubic,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AiryPalette.accent,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          '拖到目标时间格后松开',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                          ),
                        ).animate().fadeIn(duration: 420.ms).scale(
                              begin: const Offset(0.99, 0.99),
                              end: const Offset(1, 1),
                              duration: 420.ms,
                            ),
                      ),
                    ),
                  ],
                ),
            ),
            ],
          ),
      ),
    );
  }
}

class _AiryAppointmentCard extends StatefulWidget {
  const _AiryAppointmentCard({
    required this.subject,
    required this.timeText,
    required this.color,
    required this.compact,
    required this.recurring,
    super.key,
  });

  final String subject;
  final String timeText;
  final Color color;
  final bool compact;
  final bool recurring;

  @override
  State<_AiryAppointmentCard> createState() => _AiryAppointmentCardState();
}

class _AiryAppointmentCardState extends State<_AiryAppointmentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final start = base.withValues(alpha: widget.compact ? 0.9 : 0.94);
    final end = base.withValues(alpha: widget.compact ? 0.72 : 0.8);

    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: AnimatedScale(
        scale: _hovered && !widget.compact ? 1.015 : 1,
        duration: AiryTheme.quick,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: AiryTheme.quick,
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.all(widget.compact ? 1 : 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 6 : 8,
            vertical: widget.compact ? 2 : 4,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [start, end]),
            borderRadius: BorderRadius.circular(widget.compact ? 8 : 10),
            border: Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.84 : 0.66),
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: _hovered ? 0.28 : 0.18),
                blurRadius: _hovered ? 12 : 8,
                offset: Offset(0, _hovered ? 6 : 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canShowTime =
                  !widget.compact &&
                  constraints.maxHeight >= 34 &&
                  constraints.maxWidth >= 120;

              return Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subject,
                          maxLines: canShowTime ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: canShowTime ? 11 : 12,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        if (canShowTime)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.timeText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.recurring &&
                      constraints.maxHeight >= 22 &&
                      constraints.maxWidth >= 52)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.repeat_rounded,
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class CalendarEventDataSource extends CalendarDataSource {
  CalendarEventDataSource(List<Appointment> source) {
    appointments = source;
  }

  void updateAppointments(List<Appointment> source) {
    appointments = source;
    notifyListeners(CalendarDataSourceAction.reset, appointments!);
  }
}
