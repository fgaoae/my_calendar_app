import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cihxthzvavqueiwujcbe.supabase.co',
    // ⚠️ 替换为你真实的 anonKey
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

// --- 日历视图 ---
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
      for (var item in data) {
        if (item['start_time'] == null) continue;
        try {
          final startTime = DateTime.parse(item['start_time'].toString()).toLocal();
          final endTime = item['end_time'] != null 
              ? DateTime.parse(item['end_time'].toString()).toLocal() 
              : startTime.add(const Duration(hours: 1));

          // 读取 JSONB 里的重复规则
          final props = item['properties'] ?? {};
          final rrule = item['is_recurring'] == true ? props['_sys_rrule']?.toString() : null;

          appointments.add(Appointment(
            id: item['id'],
            startTime: startTime,
            endTime: endTime,
            subject: item['title']?.toString() ?? '无标题',
            notes: item['description']?.toString(),
            color: Colors.deepPurpleAccent,
            recurrenceRule: rrule, // 给 Syncfusion 传递重复规则
          ));
        } catch (e) { print("解析失败: $e"); }
      }
      _dataSource.updateAppointments(appointments);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
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

  Future<void> _updateEventTime(dynamic id, DateTime newStartTime) async {
    try {
      await Supabase.instance.client.from('events').update({
        'start_time': newStartTime.toUtc().toIso8601String(),
        'end_time': newStartTime.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      print("更新事件时间失败: $e");
    }
  }
}

// --- 数据库视图 ---
class DatabaseViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  final Stream<List<Map<String, dynamic>>> dbStream;
  const DatabaseViewWidget({super.key, required this.eventStream, required this.dbStream});
  @override
  State<DatabaseViewWidget> createState() => _DatabaseViewWidgetState();
}

class _DatabaseViewWidgetState extends State<DatabaseViewWidget> {
  String? _selectedDbId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.dbStream,
      builder: (context, dbSnapshot) {
        if (dbSnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        
        final databases = dbSnapshot.data ?? [];
        if (databases.isNotEmpty) {
          final isValidSelection = databases.any((db) => db['id'].toString() == _selectedDbId);
          if (_selectedDbId == null || !isValidSelection) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedDbId = databases.last['id'].toString());
            });
          }
        } else {
          if (_selectedDbId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedDbId = null);
            });
          }
        }

        Map<String, dynamic> currentDb = {};
        if (_selectedDbId != null && databases.isNotEmpty) {
           try {
             currentDb = databases.firstWhere((db) => db['id'].toString() == _selectedDbId);
           } catch (e) {}
        }
            
        final List<String> schema = currentDb.isNotEmpty ? List<String>.from(currentDb['schema'] ?? []) : [];

        return Scaffold(
          appBar: AppBar(
            title: const Text('多维数据库'),
            actions: [
              IconButton(
                icon: const Icon(Icons.create_new_folder),
                tooltip: '新建数据库',
                onPressed: () => _createNewDatabaseDialog(context),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('请选择或新建数据库'),
                        value: _selectedDbId,
                        items: databases.map((db) => DropdownMenuItem<String>(
                          value: db['id'].toString(),
                          child: Text(db['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedDbId = val);
                        },
                      ),
                    ),
                    if (_selectedDbId != null) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_box, size: 18),
                        label: const Text('新增属性'),
                        onPressed: () => _addNewPropertyDialog(context, currentDb),
                      ),
                    ]
                  ],
                ),
              ),
              Expanded(
                child: _selectedDbId == null 
                  ? const Center(child: Text('👈 请先在右上角新建一个数据库'))
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: widget.eventStream,
                      builder: (context, eventSnapshot) {
                        if (!eventSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                        
                        final events = eventSnapshot.data!.where((e) => e['database_id'].toString() == _selectedDbId).toList();
                        
                        if (events.isEmpty) return const Center(child: Text('暂无数据，点击右下角添加'));

                        return ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            final hasTime = event['start_time'] != null;
                            final Map<String, dynamic> props = event['properties'] ?? {};
                            
                            // 过滤掉系统内部用的重复和提醒字段，不展示在 UI 预览上
                            final displayProps = Map.from(props)..removeWhere((k, v) => k.startsWith('_sys_'));

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: ListTile(
                                title: Text(event['title']?.toString() ?? '无标题', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(hasTime ? '🕒 ${DateTime.parse(event['start_time']).toLocal().toString().substring(0, 16)}' : '📌 未排期 (草稿)'),
                                    if (event['is_recurring'] == true) const Text('🔁 重复任务', style: TextStyle(color: Colors.blue, fontSize: 12)),
                                    if (displayProps.isNotEmpty)
                                      Text('自定义属性: $displayProps', style: const TextStyle(color: Colors.deepPurple, fontSize: 12)),
                                  ],
                                ),
                                trailing: const Icon(Icons.edit_note),
                                onTap: () => _showEditEventDialog(context, event, schema, _selectedDbId!),
                              ),
                            );
                          },
                        );
                      },
                    ),
              ),
            ],
          ),
          floatingActionButton: _selectedDbId == null ? null : FloatingActionButton(
            onPressed: () => _showEditEventDialog(context, null, schema, _selectedDbId!),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _createNewDatabaseDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建数据库'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '数据库名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                await Supabase.instance.client.from('databases').insert({'name': nameCtrl.text.trim()});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          )
        ],
      ),
    );
  }

  void _addNewPropertyDialog(BuildContext context, Map<String, dynamic> currentDb) {
    final propCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加自定义属性'),
        content: TextField(controller: propCtrl, decoration: const InputDecoration(labelText: '属性名称 (例如: 分类, 优先级)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newProp = propCtrl.text.trim();
              if (newProp.isNotEmpty) {
                List<String> schema = List<String>.from(currentDb['schema'] ?? []);
                if (!schema.contains(newProp)) {
                  schema.add(newProp);
                  await Supabase.instance.client.from('databases').update({'schema': schema}).eq('id', currentDb['id']);
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('添加'),
          )
        ],
      ),
    );
  }

  // --- 🌟 核心修改：支持起止时间、重复规则、提醒设置 ---
  void _showEditEventDialog(BuildContext context, Map<String, dynamic>? existingEvent, List<String> schema, String dbId) {
    final titleCtrl = TextEditingController(text: existingEvent?['title'] ?? '');
    final descCtrl = TextEditingController(text: existingEvent?['description'] ?? ''); 
    
    DateTime? startTime = existingEvent?['start_time'] != null ? DateTime.parse(existingEvent!['start_time']).toLocal() : null;
    DateTime? endTime = existingEvent?['end_time'] != null ? DateTime.parse(existingEvent!['end_time']).toLocal() : null;
    
    Map<String, dynamic> properties = Map<String, dynamic>.from(existingEvent?['properties'] ?? {});
    bool isRecurring = existingEvent?['is_recurring'] ?? false;
    String repeatMode = properties['_sys_rrule'] ?? 'NONE'; // NONE, FREQ=DAILY, FREQ=WEEKLY, FREQ=MONTHLY
    String reminderMode = properties['_sys_reminder'] ?? 'NONE'; // NONE, 5MIN, 15MIN, 1HOUR

    Map<String, TextEditingController> dynamicCtrls = {};
    for (var prop in schema) {
      // 过滤掉系统内部变量
      if (!prop.startsWith('_sys_')) {
        dynamicCtrls[prop] = TextEditingController(text: properties[prop]?.toString() ?? '');
      }
    }

    Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime? initialDate) async {
      final date = await showDatePicker(context: ctx, initialDate: initialDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
      if (date != null && ctx.mounted) {
        final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
        if (time != null) {
          return DateTime(date.year, date.month, date.day, time.hour, time.minute);
        }
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingEvent == null ? '新建记录' : '编辑记录'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题/名称', icon: Icon(Icons.title))),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: '描述 (Description)', icon: Icon(Icons.description))),
                    const SizedBox(height: 16),
                    
                    // --- 时间设置 ---
                    Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.grey),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton(
                                onPressed: () async {
                                  final dt = await _pickDateTime(ctx, startTime);
                                  if (dt != null) setDialogState(() { 
                                    startTime = dt; 
                                    if (endTime == null || endTime!.isBefore(startTime!)) {
                                      endTime = startTime!.add(const Duration(hours: 1)); 
                                    }
                                  });
                                },
                                child: Text(startTime != null ? '开始: ${startTime.toString().substring(0, 16)}' : '设置开始时间'),
                              ),
                              if (startTime != null)
                                OutlinedButton(
                                  onPressed: () async {
                                    final dt = await _pickDateTime(ctx, endTime);
                                    if (dt != null) setDialogState(() => endTime = dt);
                                  },
                                  child: Text(endTime != null ? '结束: ${endTime.toString().substring(0, 16)}' : '设置结束时间'),
                                ),
                            ],
                          ),
                        ),
                        if (startTime != null)
                           IconButton(icon: const Icon(Icons.clear, color: Colors.red), onPressed: () => setDialogState(() { startTime = null; endTime = null; }))
                      ],
                    ),

                    // --- 重复和提醒设置 ---
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.repeat, color: Colors.grey),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: repeatMode,
                            items: const [
                              DropdownMenuItem(value: 'NONE', child: Text('不重复')),
                              DropdownMenuItem(value: 'FREQ=DAILY', child: Text('每天重复')),
                              DropdownMenuItem(value: 'FREQ=WEEKLY', child: Text('每周重复')),
                              DropdownMenuItem(value: 'FREQ=MONTHLY', child: Text('每月重复')),
                            ],
                            onChanged: (val) {
                              setDialogState(() {
                                repeatMode = val!;
                                isRecurring = (val != 'NONE');
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.notifications_active, color: Colors.grey),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: reminderMode,
                            items: const [
                              DropdownMenuItem(value: 'NONE', child: Text('不提醒')),
                              DropdownMenuItem(value: '5MIN', child: Text('提前 5 分钟')),
                              DropdownMenuItem(value: '15MIN', child: Text('提前 15 分钟')),
                              DropdownMenuItem(value: '1HOUR', child: Text('提前 1 小时')),
                            ],
                            onChanged: (val) => setDialogState(() => reminderMode = val!),
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 32),
                    if (schema.isNotEmpty) const Text('自定义属性', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    ...schema.map((prop) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          controller: dynamicCtrls[prop],
                          decoration: InputDecoration(labelText: prop, icon: const Icon(Icons.label_outline)),
                          onChanged: (val) => properties[prop] = val,
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;
                    
                    properties.removeWhere((key, value) => value == null || value.toString().trim().isEmpty);
                    
                    // 把系统规则写入 JSONB
                    if (isRecurring) {
                      properties['_sys_rrule'] = repeatMode;
                    } else {
                      properties.remove('_sys_rrule');
                    }
                    if (reminderMode != 'NONE') {
                      properties['_sys_reminder'] = reminderMode;
                    } else {
                      properties.remove('_sys_reminder');
                    }
                    
                    final payload = {
                      'database_id': dbId,
                      'title': titleCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'start_time': startTime?.toUtc().toIso8601String(),
                      'end_time': endTime?.toUtc().toIso8601String(),
                      'is_recurring': isRecurring, // 存入数据库专用字段
                      'properties': properties,
                    };

                    try {
                      if (existingEvent == null) {
                        await Supabase.instance.client.from('events').insert(payload);
                      } else {
                        await Supabase.instance.client.from('events').update(payload).eq('id', existingEvent['id']);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      print(e);
                    }
                  },
                  child: const Text('保存'),
                )
              ],
            );
          }
        );
      },
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