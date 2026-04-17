import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cihxthzvavqueiwujcbe.supabase.co',
    // ⚠️ 改成你真实 anonKey
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpaHh0aHp2YXZxdWVpd3VqY2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNTU1MDEsImV4cCI6MjA5MTkzMTUwMX0.h9ZGVLzdF2rdlj6rtJ_xGuXugO6f4Rpc8IOmhv_mTLM',
  );
  runApp(const MyCalendarApp());
}

class MyCalendarApp extends StatelessWidget {
  const MyCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1;
  late final Stream<List<Map<String, dynamic>>> _sharedEventStream;
  late final Stream<List<Map<String, dynamic>>> _sharedDbStream;

  @override
  void initState() {
    super.initState();
    _sharedEventStream = Supabase.instance.client.from('events').stream(primaryKey: ['id']);
    _sharedDbStream = Supabase.instance.client.from('databases').stream(primaryKey: ['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CalendarViewWidget(eventStream: _sharedEventStream),
          DatabaseViewWidget(eventStream: _sharedEventStream, dbStream: _sharedDbStream),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today), label: '日历'),
          NavigationDestination(icon: Icon(Icons.table_chart), label: '数据库'),
        ],
      ),
    );
  }
}

// ============ 日历视图 ============
class CalendarViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  const CalendarViewWidget({super.key, required this.eventStream});

  @override
  State<CalendarViewWidget> createState() => _CalendarViewWidgetState();
}

class _CalendarViewWidgetState extends State<CalendarViewWidget> {
  late final _EventDataSource _dataSource;
  late final StreamSubscription<List<Map<String, dynamic>>> _subscription;

  @override
  void initState() {
    super.initState();
    _dataSource = _EventDataSource([]);
    _subscription = widget.eventStream.listen((data) {
      final List<Appointment> appointments = [];
      for (final item in data) {
        if (item['start_time'] == null) continue;
        try {
          final startTime = DateTime.parse(item['start_time'].toString()).toLocal();
          final endTime = item['end_time'] != null
              ? DateTime.parse(item['end_time'].toString()).toLocal()
              : startTime.add(const Duration(hours: 1));

          final props = (item['properties'] ?? {}) as Map<String, dynamic>;
          final rrule = item['is_recurring'] == true ? props['_sys_rrule']?.toString() : null;

          appointments.add(Appointment(
            id: item['id'],
            startTime: startTime,
            endTime: endTime,
            subject: item['title']?.toString() ?? '无标题',
            notes: item['description']?.toString(),
            color: Colors.deepPurpleAccent,
            recurrenceRule: rrule,
          ));
        } catch (_) {}
      }
      _dataSource.updateAppointments(appointments);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _updateEventTime(dynamic id, DateTime newStartTime) async {
    await Supabase.instance.client.from('events').update({
      'start_time': newStartTime.toUtc().toIso8601String(),
      'end_time': newStartTime.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    }).eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的 Notion 日历')),
      body: SfCalendar(
        view: CalendarView.week,
        dataSource: _dataSource,
        allowDragAndDrop: true,
        onDragEnd: (details) {
          final app = details.appointment;
          if (app is Appointment && details.droppingTime != null) {
            _updateEventTime(app.id, details.droppingTime!);
          }
        },
      ),
    );
  }
}

// ============ 数据库视图（满足7条需求） ============
class DatabaseViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  final Stream<List<Map<String, dynamic>>> dbStream;
  const DatabaseViewWidget({
    super.key,
    required this.eventStream,
    required this.dbStream,
  });

  @override
  State<DatabaseViewWidget> createState() => _DatabaseViewWidgetState();
}

class _DatabaseViewWidgetState extends State<DatabaseViewWidget> {
  String? _selectedDbId;

  List<Map<String, dynamic>> _dbs = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  List<Map<String, dynamic>>? _localRows;
  bool _isReordering = false;

  final Set<String> _selectedEventIds = {};
  final ScrollController _hCtrl = ScrollController();

  late final StreamSubscription<List<Map<String, dynamic>>> _dbSub;
  late final StreamSubscription<List<Map<String, dynamic>>> _eventSub;

  final Map<String, double> _colWidths = {
    'title': 220,
    'start': 190,
    'end': 190,
    'repeat': 240,
    'remind': 120,
  };

  @override
  void initState() {
    super.initState();

    _dbSub = widget.dbStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _dbs = data;
        if (_dbs.isNotEmpty) {
          final valid = _dbs.any((d) => d['id'].toString() == _selectedDbId);
          if (!valid) _selectedDbId = _dbs.first['id'].toString();
        } else {
          _selectedDbId = null;
        }
        _loading = false;
      });
    });

    _eventSub = widget.eventStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _events = data;
        if (!_isReordering) {
          _localRows = null;
        }
      });
    });

    _reloadAll();
  }

  @override
  void dispose() {
    _dbSub.cancel();
    _eventSub.cancel();
    _hCtrl.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    setState(() => _loading = true);
    final dbs = await Supabase.instance.client.from('databases').select().order('created_at');
    final ev = await Supabase.instance.client.from('events').select().order('sort_order');
    if (!mounted) return;
    setState(() {
      _dbs = List<Map<String, dynamic>>.from(dbs);
      _events = List<Map<String, dynamic>>.from(ev);
      if (_dbs.isNotEmpty) _selectedDbId ??= _dbs.first['id'].toString();
      _loading = false;
      _localRows = null;
      _isReordering = false;
    });
  }

  Map<String, dynamic> get _currentDb {
    if (_selectedDbId == null) return {};
    return _dbs.firstWhere((d) => d['id'].toString() == _selectedDbId, orElse: () => {});
  }

  List<String> get _schema => List<String>.from(_currentDb['schema'] ?? []);

  Map<String, dynamic> get _propertyTypes =>
      Map<String, dynamic>.from(_currentDb['property_types'] ?? {});

  Map<String, dynamic> get _tagOptions =>
      Map<String, dynamic>.from(_currentDb['tag_options'] ?? {});

  List<Map<String, dynamic>> _buildRowsFromSource() {
    final rows = _events.where((e) => e['database_id']?.toString() == _selectedDbId).toList();
    rows.sort((a, b) => ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0) as num));
    return rows;
  }

  List<Map<String, dynamic>> get _rows => _localRows ?? _buildRowsFromSource();

  String _fmt(dynamic v) {
    if (v == null) return '';
    try {
      return DateTime.parse(v.toString()).toLocal().toString().substring(0, 16);
    } catch (_) {
      return v.toString();
    }
  }

  String _ymd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _repeatLabel(Map<String, dynamic> props) {
    final r = props['_sys_rrule']?.toString();
    if (r == null || r.isEmpty) return '';

    String freq = '';
    if (r.contains('FREQ=DAILY')) freq = '每天';
    if (r.contains('FREQ=WEEKLY')) freq = '每周';
    if (r.contains('FREQ=MONTHLY')) freq = '每月';

    final startStr = props['_sys_repeat_start']?.toString();
    final endStr = props['_sys_repeat_end']?.toString();

    final left = (startStr == null || startStr.isEmpty) ? '未设开始' : startStr.substring(0, 10);
    final right = (endStr == null || endStr.isEmpty) ? '永久' : endStr.substring(0, 10);

    return '$left - $right $freq';
  }

  String _remindLabel(Map<String, dynamic> p) {
    switch (p['_sys_reminder']?.toString()) {
      case '5MIN':
        return '5分钟前';
      case '15MIN':
        return '15分钟前';
      case '1HOUR':
        return '1小时前';
      default:
        return '';
    }
  }

  Future<void> _createDatabase() async {
    final c = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建数据库'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: '数据库名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = c.text.trim();
              if (name.isEmpty) return;
              await Supabase.instance.client.from('databases').insert({
                'name': name,
                'schema': [],
                'property_types': {},
                'tag_options': {},
              });
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDatabase(Map<String, dynamic> db) async {
    final c = TextEditingController(text: db['name']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名数据库'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: '新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = c.text.trim();
              if (name.isEmpty) return;
              await Supabase.instance.client.from('databases').update({'name': name}).eq('id', db['id']);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDatabase(Map<String, dynamic> db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除数据库'),
        content: Text('确认删除 “${db['name']}”？将同时删除该数据库下所有数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;

    final dbId = db['id'].toString();
    await Supabase.instance.client.from('events').delete().eq('database_id', dbId);
    await Supabase.instance.client.from('databases').delete().eq('id', dbId);

    if (!mounted) return;
    if (_selectedDbId == dbId) {
      final left = _dbs.where((d) => d['id'].toString() != dbId).toList();
      setState(() => _selectedDbId = left.isNotEmpty ? left.first['id'].toString() : null);
    }
  }

  // 新增属性：带类型
  Future<void> _addPropertyFromHeaderPlus() async {
    final nameCtrl = TextEditingController();
    String type = 'text'; // text | checkbox | tag

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => AlertDialog(
          title: const Text('新增属性'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '属性名称')),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: type,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('文本')),
                  DropdownMenuItem(value: 'checkbox', child: Text('复选框')),
                  DropdownMenuItem(value: 'tag', child: Text('标签')),
                ],
                onChanged: (v) => setD(() => type = v ?? 'text'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final key = nameCtrl.text.trim();
                if (key.isEmpty) return;

                final schema = List<String>.from(_schema);
                final types = Map<String, dynamic>.from(_propertyTypes);
                final tags = Map<String, dynamic>.from(_tagOptions);

                if (!schema.contains(key)) {
                  schema.add(key);
                }
                types[key] = type;
                if (type == 'tag' && tags[key] == null) {
                  tags[key] = <String>[];
                }

                await Supabase.instance.client.from('databases').update({
                  'schema': schema,
                  'property_types': types,
                  'tag_options': tags,
                }).eq('id', _currentDb['id']);

                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProperty(String key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除属性'),
        content: Text('确认删除属性“$key”？会清除该列所有数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;

    final schema = List<String>.from(_schema)..remove(key);
    final types = Map<String, dynamic>.from(_propertyTypes)..remove(key);
    final tags = Map<String, dynamic>.from(_tagOptions)..remove(key);

    await Supabase.instance.client.from('databases').update({
      'schema': schema,
      'property_types': types,
      'tag_options': tags,
    }).eq('id', _currentDb['id']);

    for (final r in _rows) {
      final props = Map<String, dynamic>.from(r['properties'] ?? {});
      if (props.containsKey(key)) {
        props.remove(key);
        await Supabase.instance.client.from('events').update({'properties': props}).eq('id', r['id']);
      }
    }
  }

  Future<void> _deleteSelectedRows() async {
    if (_selectedEventIds.isEmpty) return;
    await Supabase.instance.client.from('events').delete().inFilter('id', _selectedEventIds.toList());
    setState(() => _selectedEventIds.clear());
  }

  Future<void> _deleteOneRow(String id) async {
    await Supabase.instance.client.from('events').delete().eq('id', id);
    setState(() => _selectedEventIds.remove(id));
  }

  Future<void> _reorderRows(int oldIndex, int newIndex) async {
    if (_isReordering) return;

    final current = [..._rows];
    if (newIndex > oldIndex) newIndex -= 1;

    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);

    setState(() {
      _isReordering = true;
      _localRows = current; // 立即显示目标位置
    });

    try {
      for (int i = 0; i < current.length; i++) {
        await Supabase.instance.client
            .from('events')
            .update({'sort_order': i + 1})
            .eq('id', current[i]['id']);
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isReordering = false;
      });
    }
  }

  Future<void> _editTitle(Map<String, dynamic> row) async {
    final c = TextEditingController(text: row['title']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改名称'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              await Supabase.instance.client.from('events').update({'title': c.text.trim()}).eq('id', row['id']);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _pickDateThenTime(DateTime? initial) async {
    final base = initial ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  // 修正：只改开始，不自动冒出结束
  Future<void> _editStartTime(Map<String, dynamic> row) async {
    final oldStart = row['start_time'] != null ? DateTime.parse(row['start_time']).toLocal() : null;
    final dt = await _pickDateThenTime(oldStart);
    if (dt == null) return;

    await Supabase.instance.client.from('events').update({
      'start_time': dt.toUtc().toIso8601String(),
    }).eq('id', row['id']);
  }

  Future<void> _editEndTime(Map<String, dynamic> row) async {
    final oldStart = row['start_time'] != null ? DateTime.parse(row['start_time']).toLocal() : null;
    final oldEnd = row['end_time'] != null ? DateTime.parse(row['end_time']).toLocal() : null;
    final dt = await _pickDateThenTime(oldEnd ?? oldStart ?? DateTime.now());
    if (dt == null) return;

    if (oldStart != null && dt.isBefore(oldStart)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
      return;
    }

    await Supabase.instance.client.from('events').update({
      'end_time': dt.toUtc().toIso8601String(),
    }).eq('id', row['id']);
  }

  Future<void> _editReminder(Map<String, dynamic> row) async {
    String value = (row['properties']?['_sys_reminder']?.toString() ?? 'NONE');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提醒'),
        content: StatefulBuilder(
          builder: (_, s) => DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('不提醒')),
              DropdownMenuItem(value: '5MIN', child: Text('提前5分钟')),
              DropdownMenuItem(value: '15MIN', child: Text('提前15分钟')),
              DropdownMenuItem(value: '1HOUR', child: Text('提前1小时')),
            ],
            onChanged: (v) => s(() => value = v ?? 'NONE'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final props = Map<String, dynamic>.from(row['properties'] ?? {});
              if (value == 'NONE') {
                props.remove('_sys_reminder');
              } else {
                props['_sys_reminder'] = value;
              }
              await Supabase.instance.client.from('events').update({'properties': props}).eq('id', row['id']);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRepeat(Map<String, dynamic> row) async {
    String freq = 'NONE';
    DateTime? startDate = row['start_time'] != null ? DateTime.parse(row['start_time']).toLocal() : DateTime.now();
    DateTime? endDate;

    final oldProps = Map<String, dynamic>.from(row['properties'] ?? {});
    final oldR = oldProps['_sys_rrule']?.toString() ?? '';
    if (oldR.contains('FREQ=DAILY')) freq = 'DAILY';
    if (oldR.contains('FREQ=WEEKLY')) freq = 'WEEKLY';
    if (oldR.contains('FREQ=MONTHLY')) freq = 'MONTHLY';

    if (oldProps['_sys_repeat_start'] != null) {
      startDate = DateTime.tryParse(oldProps['_sys_repeat_start'].toString())?.toLocal() ?? startDate;
    }
    if (oldProps['_sys_repeat_end'] != null) {
      endDate = DateTime.tryParse(oldProps['_sys_repeat_end'].toString())?.toLocal();
    }

    Future<DateTime?> pickDate(DateTime? init) async {
      return showDatePicker(
        context: context,
        initialDate: init ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
    }

    String buildRRule(String f, DateTime start, DateTime? end) {
      final base = 'FREQ=$f;INTERVAL=1';
      if (end == null) return base;
      final u = DateTime(end.year, end.month, end.day, 23, 59, 59).toUtc();
      final untilStr =
          '${u.year.toString().padLeft(4, '0')}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}T${u.hour.toString().padLeft(2, '0')}${u.minute.toString().padLeft(2, '0')}${u.second.toString().padLeft(2, '0')}Z';
      return '$base;UNTIL=$untilStr';
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => AlertDialog(
          title: const Text('重复设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: freq,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'NONE', child: Text('不重复')),
                  DropdownMenuItem(value: 'DAILY', child: Text('每天')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('每周')),
                  DropdownMenuItem(value: 'MONTHLY', child: Text('每月')),
                ],
                onChanged: (v) => setD(() => freq = v ?? 'NONE'),
              ),
              if (freq != 'NONE') ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final d = await pickDate(startDate);
                    if (d != null) setD(() => startDate = d);
                  },
                  child: Text('开始日期: ${startDate == null ? '未设置' : _ymd(startDate!)}'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final d = await pickDate(endDate ?? startDate);
                    if (d != null) setD(() => endDate = d);
                  },
                  child: Text('截止日期: ${endDate == null ? '永久' : _ymd(endDate!)}'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final props = Map<String, dynamic>.from(row['properties'] ?? {});
                bool isRecurring = false;

                if (freq == 'NONE') {
                  props.remove('_sys_rrule');
                  props.remove('_sys_repeat_start');
                  props.remove('_sys_repeat_end');
                } else {
                  isRecurring = true;
                  final s = startDate ?? DateTime.now();
                  props['_sys_rrule'] = buildRRule(freq, s, endDate);
                  props['_sys_repeat_start'] = _ymd(s);
                  if (endDate != null) {
                    props['_sys_repeat_end'] = _ymd(endDate!);
                  } else {
                    props.remove('_sys_repeat_end');
                  }
                }

                await Supabase.instance.client.from('events').update({
                  'is_recurring': isRecurring,
                  'properties': props,
                }).eq('id', row['id']);

                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCustomProperty(Map<String, dynamic> row, String key) async {
    final type = _propertyTypes[key]?.toString() ?? 'text';

    if (type == 'checkbox') {
      final props = Map<String, dynamic>.from(row['properties'] ?? {});
      final current = (props[key] == true);
      props[key] = !current;
      await Supabase.instance.client.from('events').update({'properties': props}).eq('id', row['id']);
      return;
    }

    if (type == 'tag') {
      final props = Map<String, dynamic>.from(row['properties'] ?? {});
      final current = props[key]?.toString() ?? '';
      final options = List<String>.from(_tagOptions[key] ?? []);
      String selected = current;

      final newTagCtrl = TextEditingController();

      await showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (_, setD) => AlertDialog(
            title: Text('编辑标签：$key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: selected.isEmpty ? null : selected,
                  hint: const Text('选择已有标签'),
                  isExpanded: true,
                  items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                  onChanged: (v) => setD(() => selected = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newTagCtrl,
                  decoration: const InputDecoration(labelText: '新增标签并选择'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              ElevatedButton(
                onPressed: () async {
                  final input = newTagCtrl.text.trim();
                  final dbTagOptions = Map<String, dynamic>.from(_tagOptions);
                  final list = List<String>.from(dbTagOptions[key] ?? []);

                  if (input.isNotEmpty) {
                    if (!list.contains(input)) list.add(input);
                    dbTagOptions[key] = list;
                    selected = input;
                    await Supabase.instance.client.from('databases').update({
                      'tag_options': dbTagOptions,
                    }).eq('id', _currentDb['id']);
                  }

                  if (selected.isEmpty) {
                    props.remove(key);
                  } else {
                    props[key] = selected;
                  }

                  await Supabase.instance.client.from('events').update({'properties': props}).eq('id', row['id']);

                  if (!mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // text
    final c = TextEditingController(text: row['properties']?[key]?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('编辑属性：$key'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final props = Map<String, dynamic>.from(row['properties'] ?? {});
              final v = c.text.trim();
              if (v.isEmpty) {
                props.remove(key);
              } else {
                props[key] = v;
              }
              await Supabase.instance.client.from('events').update({'properties': props}).eq('id', row['id']);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _addRow() async {
    await Supabase.instance.client.from('events').insert({
      'database_id': _selectedDbId,
      'title': '未命名',
      'description': '',
      'start_time': null,
      'end_time': null,
      'is_recurring': false,
      'properties': {},
      'sort_order': _rows.length + 1,
    });
  }

  Widget _headCell(String key, String label, {bool deletable = false, VoidCallback? onDelete}) {
    final width = _colWidths[key] ?? 140;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (deletable)
                  InkWell(
                    onTap: onDelete,
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _colWidths[key] = (width + d.delta.dx).clamp(80, 420);
                  });
                },
                child: Container(width: 10, color: Colors.transparent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell({
    required String text,
    required double width,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Text(text, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildCustomPropertyCell(Map<String, dynamic> row, String key, double width) {
    final type = _propertyTypes[key]?.toString() ?? 'text';
    final props = Map<String, dynamic>.from(row['properties'] ?? {});

    if (type == 'checkbox') {
      final checked = props[key] == true;
      return Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Checkbox(
          value: checked,
          onChanged: (_) => _editCustomProperty(row, key),
        ),
      );
    }

    if (type == 'tag') {
      final v = props[key]?.toString() ?? '';
      return InkWell(
        onTap: () => _editCustomProperty(row, key),
        child: Container(
          width: width,
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: v.isEmpty
              ? const Text('')
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(v, style: const TextStyle(fontSize: 12)),
                ),
        ),
      );
    }

    return _cell(
      text: props[key]?.toString() ?? '',
      width: width,
      onTap: () => _editCustomProperty(row, key),
    );
  }

  Widget _buildRow(Map<String, dynamic> r, int i, List<String> schema) {
    final id = r['id'].toString();
    final props = Map<String, dynamic>.from(r['properties'] ?? {});
    return Container(
      key: ValueKey(id),
      color: i.isEven ? Colors.white : Colors.grey.shade50,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Checkbox(
              value: _selectedEventIds.contains(id),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedEventIds.add(id);
                  } else {
                    _selectedEventIds.remove(id);
                  }
                });
              },
            ),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const SizedBox(
              width: 34,
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ),
          _cell(text: (r['title'] ?? '').toString(), width: _colWidths['title']!, onTap: () => _editTitle(r)),
          _cell(text: _fmt(r['start_time']), width: _colWidths['start']!, onTap: () => _editStartTime(r)),
          _cell(text: _fmt(r['end_time']), width: _colWidths['end']!, onTap: () => _editEndTime(r)),
          _cell(text: _repeatLabel(props), width: _colWidths['repeat']!, onTap: () => _editRepeat(r)),
          _cell(text: _remindLabel(props), width: _colWidths['remind']!, onTap: () => _editReminder(r)),
          for (final k in schema)
            _buildCustomPropertyCell(
              r,
              k,
              _colWidths['prop_$k'] ?? 140,
            ),
          SizedBox(
            width: 44,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteOneRow(id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('数据库', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _createDatabase,
              tooltip: '新建数据库',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _dbs.isEmpty
                ? const Center(child: Text('暂无数据库'))
                : ListView.builder(
                    itemCount: _dbs.length,
                    itemBuilder: (_, i) {
                      final db = _dbs[i];
                      final id = db['id'].toString();
                      final selected = id == _selectedDbId;
                      return Material(
                        color: selected ? Colors.deepPurple.withOpacity(0.08) : Colors.transparent,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            db['name']?.toString() ?? '未命名',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedDbId = id;
                              _localRows = null;
                              _isReordering = false;
                            });
                          },
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'rename') _renameDatabase(db);
                              if (v == 'delete') _deleteDatabase(db);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('重命名')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final rows = _rows;
    final schema = _schema;

    final totalWidth = 42 +
        34 +
        _colWidths['title']! +
        _colWidths['start']! +
        _colWidths['end']! +
        _colWidths['repeat']! +
        _colWidths['remind']! +
        schema.fold<double>(0, (sum, k) => sum + (_colWidths['prop_$k'] ?? 140)) +
        56 +
        44;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库'),
        actions: [
          IconButton(onPressed: _reloadAll, icon: const Icon(Icons.sync)),
          if (_selectedEventIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _deleteSelectedRows,
                icon: const Icon(Icons.delete),
                label: Text('删除选中(${_selectedEventIds.length})'),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: _selectedDbId == null
                ? const Center(child: Text('请先在左侧新建并选择数据库'))
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _hCtrl,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: totalWidth,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(width: 42),
                                    const SizedBox(width: 34),
                                    _headCell('title', '名称'),
                                    _headCell('start', '开始时间'),
                                    _headCell('end', '结束时间'),
                                    _headCell('repeat', '重复'),
                                    _headCell('remind', '提醒'),
                                    for (final k in schema)
                                      _headCell(
                                        'prop_$k',
                                        '$k (${_propertyTypes[k] ?? 'text'})',
                                        deletable: true,
                                        onDelete: () => _deleteProperty(k),
                                      ),
                                    Container(
                                      width: 56,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        border: Border(right: BorderSide(color: Colors.grey.shade300)),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.add, size: 18),
                                        onPressed: _addPropertyFromHeaderPlus,
                                      ),
                                    ),
                                    const SizedBox(width: 44),
                                  ],
                                ),
                                Expanded(
                                  child: IgnorePointer(
                                    ignoring: _isReordering,
                                    child: ReorderableListView.builder(
                                      itemCount: rows.length,
                                      onReorder: _reorderRows,
                                      buildDefaultDragHandles: false,
                                      itemBuilder: (_, i) => _buildRow(rows[i], i, schema),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addRow,
                            icon: const Icon(Icons.add),
                            label: const Text('新增一行'),
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
}
class _EventDataSource extends CalendarDataSource {
  _EventDataSource(List<Appointment> source) {
    appointments = source;
  }

  void updateAppointments(List<Appointment> newAppointments) {
    appointments = newAppointments;
    notifyListeners(CalendarDataSourceAction.reset, newAppointments);
  }
}