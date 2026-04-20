import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import '../theme/airy_theme.dart';
import '../utils/date_helpers.dart';
import '../utils/rrule_builder.dart';
import '../widgets/airy_components.dart';

class DatabaseViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  final Stream<List<Map<String, dynamic>>> dbStream;
  final ValueListenable<int> syncTick;
  final VoidCallback requestSync;
  const DatabaseViewWidget({
    super.key,
    required this.eventStream,
    required this.dbStream,
    required this.syncTick,
    required this.requestSync,
  });

  @override
  State<DatabaseViewWidget> createState() => _DatabaseViewWidgetState();
}

class _DatabaseViewWidgetState extends State<DatabaseViewWidget> {
  String? _selectedDbId;

  List<Map<String, dynamic>> _dbs = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _isRefreshing = false;
  int _refreshTasks = 0;

  List<Map<String, dynamic>>? _localRows;
  bool _isReordering = false;
  String? _hoveredRowId;
  String? _hoveredSidebarDbId;

  final Set<String> _selectedEventIds = {};
  final ScrollController _hCtrl = ScrollController();

  late final StreamSubscription<List<Map<String, dynamic>>> _dbSub;
  late final StreamSubscription<List<Map<String, dynamic>>> _eventSub;
  late final VoidCallback _syncListener;

  Timer? _syncDebounce;

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
        _dbs = data
            .where(
              (d) => d['name']?.toString() != kHiddenDatabaseName,
            )
            .toList();
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
        _events = List<Map<String, dynamic>>.from(data);
        _localRows = null;
        _isReordering = false;
      });
    });

    _syncListener = () {
      if (!mounted) return;
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        unawaited(_fetchEventsNow());
      });
    };
    widget.syncTick.addListener(_syncListener);

    _reloadAll();
  }

  @override
  void dispose() {
    widget.syncTick.removeListener(_syncListener);
    _syncDebounce?.cancel();
    _dbSub.cancel();
    _eventSub.cancel();
    _hCtrl.dispose();
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

  Future<void> _reloadAll() async {
    _startRefresh();
    try {
      setState(() => _loading = true);
      final dbs = await Supabase.instance.client
          .from('databases')
          .select()
          .order('created_at');
      final ev = await Supabase.instance.client
          .from('events')
          .select()
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _dbs = List<Map<String, dynamic>>.from(dbs)
            .where(
              (d) => d['name']?.toString() != kHiddenDatabaseName,
            )
            .toList();
        _events = List<Map<String, dynamic>>.from(ev);
        if (_dbs.isNotEmpty) _selectedDbId ??= _dbs.first['id'].toString();
        _loading = false;
        _localRows = null;
        _isReordering = false;
      });
    } finally {
      _endRefresh();
    }
  }

  Future<void> _fetchEventsNow() async {
    _startRefresh();
    try {
      final fresh = await Supabase.instance.client
          .from('events')
          .select()
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _events = List<Map<String, dynamic>>.from(fresh);
        _localRows = null;
        _isReordering = false;
      });
    } finally {
      _endRefresh();
    }
  }

  Future<void> _afterEventWrite() async {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_fetchEventsNow());
    });
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

  Map<String, dynamic> get _currentDb {
    if (_selectedDbId == null) return {};
    return _dbs.firstWhere(
      (d) => d['id'].toString() == _selectedDbId,
      orElse: () => {},
    );
  }

  List<String> get _schema => List<String>.from(_currentDb['schema'] ?? []);

  Map<String, dynamic> get _propertyTypes =>
      Map<String, dynamic>.from(_currentDb['property_types'] ?? {});

  Map<String, dynamic> get _tagOptions =>
      Map<String, dynamic>.from(_currentDb['tag_options'] ?? {});

  int _eventSortOrder(Map<String, dynamic> event) {
    return (event['sort_order'] as num?)?.toInt() ?? 0;
  }

  DateTime? _eventCreatedAt(Map<String, dynamic> event) {
    final raw = event['created_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  int _compareEventsByOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final bySortOrder = _eventSortOrder(a).compareTo(_eventSortOrder(b));
    if (bySortOrder != 0) return bySortOrder;

    final aCreated = _eventCreatedAt(a);
    final bCreated = _eventCreatedAt(b);
    if (aCreated != null && bCreated != null) {
      final byCreated = aCreated.compareTo(bCreated);
      if (byCreated != 0) return byCreated;
    } else if (aCreated != null) {
      return -1;
    } else if (bCreated != null) {
      return 1;
    }

    final aId = a['id']?.toString() ?? '';
    final bId = b['id']?.toString() ?? '';
    return aId.compareTo(bId);
  }

  List<Map<String, dynamic>> _buildRowsFromSource() {
    final rows = _events
        .where((e) => e['database_id']?.toString() == _selectedDbId)
        .toList();
    rows.sort(_compareEventsByOrder);
    return rows;
  }

  List<Map<String, dynamic>> get _rows => _localRows ?? _buildRowsFromSource();

  void _patchLocalEventById(String id, Map<String, dynamic> updates) {
    final idx = _events.indexWhere(
      (e) => e['id'] != null && e['id'].toString() == id,
    );
    if (idx < 0) return;
    final next = List<Map<String, dynamic>>.from(_events);
    final merged = Map<String, dynamic>.from(next[idx]);
    merged.addAll(updates);
    next[idx] = merged;
    if (!mounted) return;
    setState(() {
      _events = next;
      _localRows = null;
      _isReordering = false;
    });
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    try {
      return DateTime.parse(v.toString()).toLocal().toString().substring(0, 16);
    } catch (_) {
      return v.toString();
    }
  }

  Color _databaseColor(String? dbId) {
    return AiryPalette.databaseAccentForId(dbId);
  }

  String _repeatLabel(Map<String, dynamic> props) {
    final r = props['_sys_rrule']?.toString();
    if (r == null || r.isEmpty) return '';

    String freq = '';
    if (r.contains('FREQ=DAILY')) freq = '每天';
    if (r.contains('FREQ=WEEKLY')) freq = '每周';
    if (r.contains('FREQ=MONTHLY')) freq = '每月';

    final startStr = props['_sys_repeat_start']?.toString();
    final endStr = props['_sys_repeat_end']?.toString();

    final left = (startStr == null || startStr.isEmpty)
        ? '未设开始'
        : startStr.substring(0, 10);
    final right = (endStr == null || endStr.isEmpty)
        ? '永久'
        : endStr.substring(0, 10);

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
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: const Text('新建数据库'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: '数据库名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
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
                widget.requestSync();
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDatabase(Map<String, dynamic> db) async {
    final c = TextEditingController(text: db['name']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: const Text('重命名数据库'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: '新名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = c.text.trim();
                if (name.isEmpty) return;
                await Supabase.instance.client
                    .from('databases')
                    .update({'name': name})
                    .eq('id', db['id']);
                if (!mounted) return;
                Navigator.pop(context);
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDatabase(Map<String, dynamic> db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: const Text('删除数据库'),
          content: Text('确认删除 "${db['name']}"？将同时删除该数据库下所有数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AiryPalette.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final dbId = db['id'].toString();
    await Supabase.instance.client
        .from('events')
        .delete()
        .eq('database_id', dbId);
    await Supabase.instance.client.from('databases').delete().eq('id', dbId);

    if (!mounted) return;
    if (_selectedDbId == dbId) {
      final left = _dbs.where((d) => d['id'].toString() != dbId).toList();
      setState(
        () => _selectedDbId = left.isNotEmpty
            ? left.first['id'].toString()
            : null,
      );
    }
    widget.requestSync();
    await _afterEventWrite();
  }

  Future<void> _addPropertyFromHeaderPlus() async {
    final nameCtrl = TextEditingController();
    String type = 'text';
    List<String> tagOptions = [];
    final newTagCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => _buildAnimatedDialog(
          AlertDialog(
          title: const Text('新增属性'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '属性名称'),
                  ),
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
                  if (type == 'tag') ...[
                    const SizedBox(height: 16),
                    const Text(
                      '标签选项管理',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newTagCtrl,
                      decoration: const InputDecoration(
                        labelText: '输入标签名称',
                        hintText: '如：优先级、状态等',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        final tagName = newTagCtrl.text.trim();
                        if (tagName.isNotEmpty && !tagOptions.contains(tagName)) {
                          setD(() {
                            tagOptions.add(tagName);
                            newTagCtrl.clear();
                          });
                        }
                      },
                      child: const Text('添加标签'),
                    ),
                    if (tagOptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已有标签 (${tagOptions.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tagOptions.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AiryPalette.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(tag, style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () => setD(() => tagOptions.remove(tag)),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final key = nameCtrl.text.trim();
                if (key.isEmpty) return;

                final schema = List<String>.from(_schema);
                final types = Map<String, dynamic>.from(_propertyTypes);
                final tags = Map<String, dynamic>.from(_tagOptions);

                if (!schema.contains(key)) schema.add(key);
                types[key] = type;
                if (type == 'tag') {
                  tags[key] = tagOptions;
                }

                await Supabase.instance.client
                    .from('databases')
                    .update({
                      'schema': schema,
                      'property_types': types,
                      'tag_options': tags,
                    })
                    .eq('id', _currentDb['id']);

                // Immediately update local database list for instant UI reflection
                if (!mounted) return;
                final idx = _dbs.indexWhere((d) => d['id'].toString() == _currentDb['id']);
                if (idx >= 0) {
                  final updated = Map<String, dynamic>.from(_dbs[idx]);
                  updated['schema'] = schema;
                  updated['property_types'] = types;
                  updated['tag_options'] = tags;
                  final newList = [..._dbs];
                  newList[idx] = updated;
                  setState(() {
                    _dbs = newList;
                  });
                }
                Navigator.pop(context);
                await _reloadAll();
                widget.requestSync();
              },
              child: const Text('添加'),
            ),
          ],
        ),
        ),
      ),
    );
    nameCtrl.dispose();
    newTagCtrl.dispose();
  }

  Future<void> _editPropertyTags(String key) async {
    final newTagCtrl = TextEditingController();
    List<String> currentTags = List<String>.from(_tagOptions[key] ?? []);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => _buildAnimatedDialog(
          AlertDialog(
          title: Text('编辑标签选项：$key'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: newTagCtrl,
                    decoration: const InputDecoration(
                      labelText: '输入新标签',
                      hintText: '如：高、中、低',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      final tagName = newTagCtrl.text.trim();
                      if (tagName.isNotEmpty && !currentTags.contains(tagName)) {
                        setD(() {
                          currentTags = [...currentTags, tagName];
                          newTagCtrl.clear();
                        });
                      }
                    },
                    child: const Text('添加标签'),
                  ),
                  if (currentTags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '现有标签',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: currentTags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AiryPalette.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tag, style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    setD(() {
                                      currentTags = currentTags.where((t) => t != tag).toList();
                                    });
                                  },
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '暂无标签选项',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final tags = Map<String, dynamic>.from(_tagOptions);
                tags[key] = currentTags;

                await Supabase.instance.client
                    .from('databases')
                    .update({'tag_options': tags})
                    .eq('id', _currentDb['id']);

                if (!mounted) {
                  return;
                }
                final idx = _dbs.indexWhere((d) => d['id'].toString() == _currentDb['id']);
                if (idx >= 0) {
                  final updated = Map<String, dynamic>.from(_dbs[idx]);
                  updated['tag_options'] = tags;
                  final newList = [..._dbs];
                  newList[idx] = updated;
                  setState(() {
                    _dbs = newList;
                  });
                }
                Navigator.pop(context);
                await _reloadAll();
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
        ),
      ),
    );
    newTagCtrl.dispose();
  }

  Future<void> _deleteProperty(String key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: const Text('删除属性'),
          content: Text('确认删除属性"$key"？会清除该列所有数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AiryPalette.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final schema = List<String>.from(_schema)..remove(key);
    final types = Map<String, dynamic>.from(_propertyTypes)..remove(key);
    final tags = Map<String, dynamic>.from(_tagOptions)..remove(key);

    await Supabase.instance.client
        .from('databases')
        .update({
          'schema': schema,
          'property_types': types,
          'tag_options': tags,
        })
        .eq('id', _currentDb['id']);

    for (final r in _rows) {
      final props = Map<String, dynamic>.from(r['properties'] ?? {});
      if (props.containsKey(key)) {
        props.remove(key);
        await Supabase.instance.client
            .from('events')
            .update({'properties': props})
            .eq('id', r['id']);
      }
    }

    // Immediately update local database list for instant UI reflection
    if (!mounted) return;
    final idx = _dbs.indexWhere((d) => d['id'].toString() == _currentDb['id']);
    if (idx >= 0) {
      final updated = Map<String, dynamic>.from(_dbs[idx]);
      updated['schema'] = schema;
      updated['property_types'] = types;
      updated['tag_options'] = tags;
      final newList = [..._dbs];
      newList[idx] = updated;
      setState(() {
        _dbs = newList;
      });
    }
    widget.requestSync();
    await _reloadAll();
  }

  Future<void> _deleteSelectedRows() async {
    if (_selectedEventIds.isEmpty) return;
    final idsToDelete = _selectedEventIds.toList();
    
    if (!mounted) return;
    setState(() {
      _events = _events
          .where((e) =>
              e['id'] == null || !idsToDelete.contains(e['id'].toString()))
          .toList();
      _localRows = null;
      _selectedEventIds.clear();
    });

    try {
      await Supabase.instance.client
          .from('events')
          .delete()
          .inFilter('id', idsToDelete);
    } catch (_) {
      await _fetchEventsNow();
    }
    widget.requestSync();
  }

  Future<void> _deleteOneRow(String id) async {
    if (!mounted) return;
    setState(() {
      _events = _events
          .where((e) => e['id'] == null || e['id'].toString() != id)
          .toList();
      _localRows = null;
      _selectedEventIds.remove(id);
    });

    try {
      await Supabase.instance.client.from('events').delete().eq('id', id);
    } catch (_) {
      await _fetchEventsNow();
    }
    widget.requestSync();
  }

  Future<void> _reorderRows(int oldIndex, int newIndex) async {
    if (_isReordering) return;

    final current = [..._rows];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);

    setState(() {
      _isReordering = true;
      _localRows = current;
    });

    try {
      for (int i = 0; i < current.length; i++) {
        await Supabase.instance.client
            .from('events')
            .update({'sort_order': i + 1})
            .eq('id', current[i]['id']);
      }
    } finally {
      if (mounted) {
        setState(() => _isReordering = false);
        widget.requestSync();
      }
    }
  }

  Future<void> _editTitle(Map<String, dynamic> row) async {
    final c = TextEditingController(text: row['title']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: const Text('修改名称'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = c.text.trim();
                final id = row['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _patchLocalEventById(id, {'title': newTitle});
                }

                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({'title': newTitle})
                      .eq('id', row['id']);
                } catch (_) {
                  if (id != null && id.isNotEmpty) {
                    await _fetchEventsNow();
                  }
                }
                if (!mounted) return;
                Navigator.pop(context);
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStartTime(Map<String, dynamic> row) async {
    final oldStart = row['start_time'] != null
        ? DateTime.parse(row['start_time']).toLocal()
        : null;
    final dt = await DateHelper.pickDateThenTime(context, oldStart);
    if (dt == null) return;

    final newStart = dt.toUtc().toIso8601String();
    final id = row['id']?.toString();
    if (id != null && id.isNotEmpty) {
      _patchLocalEventById(id, {'start_time': newStart});
    }

    try {
      await Supabase.instance.client
          .from('events')
          .update({'start_time': newStart})
          .eq('id', row['id']);
    } catch (_) {
      if (id != null && id.isNotEmpty) {
        await _fetchEventsNow();
      }
    }
    widget.requestSync();
  }

  Future<void> _editEndTime(Map<String, dynamic> row) async {
    final oldStart = row['start_time'] != null
        ? DateTime.parse(row['start_time']).toLocal()
        : null;
    final oldEnd = row['end_time'] != null
        ? DateTime.parse(row['end_time']).toLocal()
        : null;
    final dt = await DateHelper.pickDateThenTime(context, oldEnd ?? oldStart ?? DateTime.now());
    if (dt == null) return;
    if (!mounted) return;

    if (oldStart != null && dt.isBefore(oldStart)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
      return;
    }

    final newEnd = dt.toUtc().toIso8601String();
    final id = row['id']?.toString();
    if (id != null && id.isNotEmpty) {
      _patchLocalEventById(id, {'end_time': newEnd});
    }

    try {
      await Supabase.instance.client
          .from('events')
          .update({'end_time': newEnd})
          .eq('id', row['id']);
    } catch (_) {
      if (id != null && id.isNotEmpty) {
        await _fetchEventsNow();
      }
    }
    widget.requestSync();
  }

  Future<void> _editReminder(Map<String, dynamic> row) async {
    String value = (row['properties']?['_sys_reminder']?.toString() ?? 'NONE');
    await showDialog(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final props = Map<String, dynamic>.from(row['properties'] ?? {});
                if (value == 'NONE') {
                  props.remove('_sys_reminder');
                } else {
                  props['_sys_reminder'] = value;
                }
                final id = row['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _patchLocalEventById(id, {'properties': props});
                }

                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({'properties': props})
                      .eq('id', row['id']);
                } catch (_) {
                  if (id != null && id.isNotEmpty) {
                    await _fetchEventsNow();
                  }
                }
                if (!mounted) return;
                Navigator.pop(context);
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRepeat(Map<String, dynamic> row) async {
    String freq = 'NONE';
    DateTime? startDate = row['start_time'] != null
        ? DateTime.parse(row['start_time']).toLocal()
        : DateTime.now();
    DateTime? endDate;

    final oldProps = Map<String, dynamic>.from(row['properties'] ?? {});
    final oldR = oldProps['_sys_rrule']?.toString() ?? '';
    if (oldR.contains('FREQ=DAILY')) freq = 'DAILY';
    if (oldR.contains('FREQ=WEEKLY')) freq = 'WEEKLY';
    if (oldR.contains('FREQ=MONTHLY')) freq = 'MONTHLY';

    if (oldProps['_sys_repeat_start'] != null) {
      startDate =
          DateTime.tryParse(
            oldProps['_sys_repeat_start'].toString(),
          )?.toLocal() ??
          startDate;
    }
    if (oldProps['_sys_repeat_end'] != null) {
      endDate = DateTime.tryParse(
        oldProps['_sys_repeat_end'].toString(),
      )?.toLocal();
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => _buildAnimatedDialog(
          AlertDialog(
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
                    final d = await DateHelper.pickDate(context, startDate);
                    if (d != null) setD(() => startDate = d);
                  },
                  child: Text(
                    '开始日期: ${startDate == null ? '未设置' : DateHelper.formatDate(startDate!)}',
                  ),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final d = await DateHelper.pickDate(context, endDate ?? startDate);
                    if (d != null) setD(() => endDate = d);
                  },
                  child: Text(
                    '截止日期: ${endDate == null ? '永久' : DateHelper.formatDate(endDate!)}',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final props = Map<String, dynamic>.from(
                  row['properties'] ?? {},
                );
                bool isRecurring = false;

                if (freq == 'NONE') {
                  props.remove('_sys_rrule');
                  props.remove('_sys_repeat_start');
                  props.remove('_sys_repeat_end');
                  props.remove('_sys_exdates');
                } else {
                  isRecurring = true;
                  final s = startDate ?? DateTime.now();
                  props['_sys_rrule'] = RRuleBuilder.build(
                    frequency: freq,
                    startDate: s,
                    endDate: endDate,
                  );
                  props['_sys_repeat_start'] = DateHelper.formatDate(s);
                  if (endDate != null) {
                    props['_sys_repeat_end'] = DateHelper.formatDate(endDate!);
                  } else {
                    props.remove('_sys_repeat_end');
                  }
                }

                final id = row['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _patchLocalEventById(
                    id,
                    {'is_recurring': isRecurring, 'properties': props},
                  );
                }

                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({'is_recurring': isRecurring, 'properties': props})
                      .eq('id', row['id']);
                } catch (_) {
                  if (id != null && id.isNotEmpty) {
                    await _fetchEventsNow();
                  }
                }

                if (!mounted) return;
                Navigator.pop(context);
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
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
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) {
        _patchLocalEventById(id, {'properties': props});
      }

      try {
        await Supabase.instance.client
            .from('events')
            .update({'properties': props})
            .eq('id', row['id']);
      } catch (_) {
        if (id != null && id.isNotEmpty) {
          await _fetchEventsNow();
        }
      }
      widget.requestSync();
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
          builder: (_, setD) => _buildAnimatedDialog(
            AlertDialog(
            title: Text('为 $key 选择标签'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '已有标签',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  if (options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
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
                      child: SingleChildScrollView(
                        child: Column(
                          children: options.map((tag) {
                            final isSelected = selected == tag;
                            return InkWell(
                              onTap: () => setD(() => selected = tag),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AiryPalette.accent.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  border: isSelected
                                      ? Border.all(
                                          color: AiryPalette.accent,
                                          width: 2,
                                        )
                                      : Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? AiryPalette.accent
                                              : AiryPalette.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check,
                                        color: AiryPalette.accent,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    '或选择不设置标签',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => setD(() => selected = ''),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected.isEmpty
                            ? Colors.grey.withValues(alpha: 0.15)
                            : Colors.transparent,
                        border: selected.isEmpty
                            ? Border.all(
                                color: Colors.grey,
                                width: 2,
                              )
                            : Border.all(
                                color: Colors.grey.shade200,
                              ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '（不设置）',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          if (selected.isEmpty)
                            const Icon(
                              Icons.check,
                              color: Colors.grey,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  newTagCtrl.dispose();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selected.isEmpty) {
                    props.remove(key);
                  } else {
                    props[key] = selected;
                  }

                  final id = row['id']?.toString();
                  if (id != null && id.isNotEmpty) {
                    _patchLocalEventById(id, {'properties': props});
                  }

                  try {
                    await Supabase.instance.client
                        .from('events')
                        .update({'properties': props})
                        .eq('id', row['id']);
                  } catch (_) {
                    if (id != null && id.isNotEmpty) {
                      await _fetchEventsNow();
                    }
                  }

                  if (!mounted) {
                    newTagCtrl.dispose();
                    return;
                  }
                  Navigator.pop(context);
                  widget.requestSync();
                  newTagCtrl.dispose();
                },
                child: const Text('保存'),
              ),
            ],
          ),
          ),
        ),
      );
      return;
    }

    final c = TextEditingController(
      text: row['properties']?[key]?.toString() ?? '',
    );
    await showDialog(
      context: context,
      builder: (_) => _buildAnimatedDialog(
        AlertDialog(
          title: Text('编辑属性：$key'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final props = Map<String, dynamic>.from(row['properties'] ?? {});
                final v = c.text.trim();
                if (v.isEmpty) {
                  props.remove(key);
                } else {
                  props[key] = v;
                }
                final id = row['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _patchLocalEventById(id, {'properties': props});
                }

                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({'properties': props})
                      .eq('id', row['id']);
                } catch (_) {
                  if (id != null && id.isNotEmpty) {
                    await _fetchEventsNow();
                  }
                }
                if (!mounted) return;
                Navigator.pop(context);
                widget.requestSync();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRow() async {
    final maxSortOrder = _rows.fold<int>(0, (maxValue, row) {
      final current = _eventSortOrder(row);
      return current > maxValue ? current : maxValue;
    });

    final inserted = await Supabase.instance.client.from('events').insert({
      'database_id': _selectedDbId,
      'title': '未命名',
      'description': '',
      'start_time': null,
      'end_time': null,
      'is_recurring': false,
      'properties': {},
      'sort_order': maxSortOrder + 1,
    }).select().single();

    if (!mounted) return;
    setState(() {
      _events = [..._events, Map<String, dynamic>.from(inserted)];
      _localRows = null;
      _isReordering = false;
    });
  }

  Widget _headCell(
    String key,
    String label, {
    bool deletable = false,
    bool editable = false,
    VoidCallback? onDelete,
    VoidCallback? onEdit,
  }) {
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
              color: AiryPalette.panelTint.withValues(alpha: 0.95),
              border: Border(
                right: BorderSide(color: AiryPalette.border.withValues(alpha: 0.9)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AiryPalette.textSecondary,
                    ),
                  ),
                ),
                if (editable)
                  InkWell(
                    onTap: onEdit,
                    child: const Icon(Icons.edit, size: 16, color: AiryPalette.accent),
                  ),
                if (deletable)
                  InkWell(
                    onTap: onDelete,
                    child: const Icon(Icons.close, size: 16, color: AiryPalette.danger),
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
            right: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
            bottom: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
          ),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AiryPalette.textPrimary),
        ),
      ),
    );
  }

  Widget _buildCustomPropertyCell(
    Map<String, dynamic> row,
    String key,
    double width,
  ) {
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
            right: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
            bottom: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
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
              right: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
              bottom: BorderSide(color: AiryPalette.border.withValues(alpha: 0.85)),
            ),
          ),
          child: v.isEmpty
              ? const Text('')
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AiryPalette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    v,
                    style: const TextStyle(fontSize: 12, color: AiryPalette.accent),
                  ),
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
    final selected = _selectedEventIds.contains(id);
    final hovered = _hoveredRowId == id;
    return MouseRegion(
      key: ValueKey('row-$id'),
      onEnter: (_) {
        if (_hoveredRowId != id) {
          setState(() => _hoveredRowId = id);
        }
      },
      onExit: (_) {
        if (_hoveredRowId == id) {
          setState(() => _hoveredRowId = null);
        }
      },
      child: AnimatedContainer(
        duration: AiryTheme.quick,
        curve: Curves.easeOutCubic,
        key: ValueKey(id),
        color: selected
            ? AiryPalette.accentSoft.withValues(alpha: 0.62)
            : (hovered
                  ? AiryPalette.panelTint.withValues(alpha: 0.8)
                  : (i.isEven
                        ? AiryPalette.panel.withValues(alpha: 0.76)
                        : AiryPalette.panelTint.withValues(alpha: 0.6))),
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
                child: Icon(Icons.drag_indicator, size: 18, color: AiryPalette.accent),
              ),
            ),
            _cell(
              text: (r['title'] ?? '').toString(),
              width: _colWidths['title']!,
              onTap: () => _editTitle(r),
            ),
            _cell(
              text: _fmt(r['start_time']),
              width: _colWidths['start']!,
              onTap: () => _editStartTime(r),
            ),
            _cell(
              text: _fmt(r['end_time']),
              width: _colWidths['end']!,
              onTap: () => _editEndTime(r),
            ),
            _cell(
              text: _repeatLabel(props),
              width: _colWidths['repeat']!,
              onTap: () => _editRepeat(r),
            ),
            _cell(
              text: _remindLabel(props),
              width: _colWidths['remind']!,
              onTap: () => _editReminder(r),
            ),
            for (final k in schema)
              _buildCustomPropertyCell(r, k, _colWidths['prop_$k'] ?? 140),
            SizedBox(
              width: 44,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: AiryPalette.danger),
                onPressed: () => _deleteOneRow(id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: AiryPanel(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: const Text(
                  '数据库',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add, color: AiryPalette.accent),
                  onPressed: _createDatabase,
                  tooltip: '新建数据库',
                ),
              ),
              Divider(height: 1, color: AiryPalette.border.withValues(alpha: 0.9)),
              Expanded(
                child: _dbs.isEmpty
                    ? const Center(child: Text('暂无数据库'))
                    : ListView.builder(
                        itemCount: _dbs.length,
                        itemBuilder: (_, i) {
                          final db = _dbs[i];
                          final id = db['id'].toString();
                          final selected = id == _selectedDbId;
                          final hovered = _hoveredSidebarDbId == id;
                          final dbColor = _databaseColor(id);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: MouseRegion(
                              onEnter: (_) {
                                if (_hoveredSidebarDbId != id) {
                                  setState(() => _hoveredSidebarDbId = id);
                                }
                              },
                              onExit: (_) {
                                if (_hoveredSidebarDbId == id) {
                                  setState(() => _hoveredSidebarDbId = null);
                                }
                              },
                              child: AnimatedContainer(
                                duration: AiryTheme.quick,
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? dbColor.withValues(alpha: 0.2)
                                      : (hovered
                                            ? dbColor.withValues(alpha: 0.09)
                                            : Colors.transparent),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? dbColor.withValues(alpha: 0.44)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: AnimatedContainer(
                                    duration: AiryTheme.quick,
                                    curve: Curves.easeOutCubic,
                                    width: selected ? 10 : 8,
                                    height: selected ? 10 : 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: dbColor.withValues(
                                        alpha: selected ? 1 : (hovered ? 0.85 : 0.68),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: dbColor.withValues(alpha: 0.26),
                                          blurRadius: selected ? 8 : 5,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  title: Text(
                                    db['name']?.toString() ?? '未命名',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? AiryPalette.textPrimary
                                          : AiryPalette.textSecondary,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
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
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      PopupMenuItem(value: 'delete', child: Text('删除')),
                                    ],
                                  ),
                                ),
                              ),
                            )
                                .animate(delay: (80 + i * 35).ms)
                                .fadeIn(duration: 300.ms)
                                .slideX(begin: -0.04, end: 0, duration: 300.ms),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
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

    final rows = _rows;
    final schema = _schema;

    final totalWidth =
        42 +
        34 +
        _colWidths['title']! +
        _colWidths['start']! +
        _colWidths['end']! +
        _colWidths['repeat']! +
        _colWidths['remind']! +
        schema.fold<double>(
          0,
          (sum, k) => sum + (_colWidths['prop_$k'] ?? 140),
        ) +
        56 +
        44;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('数据库'),
        actions: [
          AirySyncStatus(
            isSyncing: _isRefreshing,
            keyPrefix: 'database',
          ),
          AirySyncButton(
            isSyncing: _isRefreshing,
            keyPrefix: 'database',
            onPressed: () {
              unawaited(_reloadAll());
            },
          ),
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
      body: AiryBackground(
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(
              child: _selectedDbId == null
                  ? const Center(child: Text('请先在左侧新建并选择数据库'))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                      child: AiryPanel(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: AiryTheme.quick,
                              curve: Curves.easeOutCubic,
                              height: _isRefreshing ? 3 : 0,
                              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: const LinearProgressIndicator(
                                  backgroundColor: AiryPalette.accentSoft,
                                  color: AiryPalette.accent,
                                ),
                              ),
                            ),
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
                                              editable: _propertyTypes[k]?.toString() == 'tag',
                                              onDelete: () => _deleteProperty(k),
                                              onEdit: _propertyTypes[k]?.toString() == 'tag' ? () => _editPropertyTags(k) : null,
                                            ),
                                          Container(
                                            width: 56,
                                            height: 42,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: AiryPalette.panelTint.withValues(alpha: 0.95),
                                              border: Border(
                                                right: BorderSide(
                                                  color: AiryPalette.border.withValues(alpha: 0.9),
                                                ),
                                              ),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(Icons.add, size: 18, color: AiryPalette.accent),
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
                      ).animate().fadeIn(duration: 420.ms).slideY(begin: 0.03, end: 0),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
