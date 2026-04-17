import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'dart:async';
// --- 1. 程序入口 ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cihxthzvavqueiwujcbe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpaHh0aHp2YXZxdWVpd3VqY2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNTU1MDEsImV4cCI6MjA5MTkzMTUwMX0.h9ZGVLzdF2rdlj6rtJ_xGuXugO6f4Rpc8IOmhv_mTLM',
  );
  runApp(const MyCalendarApp());
}

// --- 2. 根应用 ---
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

// --- 3. 带有底部导航的主界面 ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  // 🌟 修复关键：声明一个全局唯一的事件流
  late final Stream<List<Map<String, dynamic>>> _sharedEventStream;

  @override
  void initState() {
    super.initState();
    // 🌟 修复关键：整个应用只发起这一次订阅，并且去掉了引发错误的 order 排序
    _sharedEventStream = Supabase.instance.client.from('events').stream(primaryKey: ['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 🌟 修复关键：将共享流传递给子组件
          CalendarViewWidget(eventStream: _sharedEventStream),
          DatabaseViewWidget(eventStream: _sharedEventStream),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart),
            label: '数据库',
          ),
        ],
      ),
    );
  }
}

// --- 4. 日历视图 ---
class CalendarViewWidget extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> eventStream;
  const CalendarViewWidget({super.key, required this.eventStream});
  
  @override
  State<CalendarViewWidget> createState() => _CalendarViewWidgetState();
}

class _CalendarViewWidgetState extends State<CalendarViewWidget> {
  // 1. 持久化的数据源，日历不会被销毁
  late final _EventDataSource _dataSource;
  // 2. 监听流的订阅器
  late final StreamSubscription<List<Map<String, dynamic>>> _subscription;

  @override
  void initState() {
    super.initState();
    _dataSource = _EventDataSource([]);
    
    // 3. 在后台监听 Supabase 的实时流，而不重建日历 Widget
    _subscription = widget.eventStream.listen((data) {
      final List<Appointment> appointments = [];
      for (var item in data) {
        if (item['start_time'] == null) continue;
        try {
          final DateTime startTime = DateTime.parse(item['start_time'].toString()).toLocal();
          final DateTime endTime = item['end_time'] != null 
              ? DateTime.parse(item['end_time'].toString()).toLocal() 
              : startTime.add(const Duration(hours: 1));

          appointments.add(Appointment(
            id: item['id'],
            startTime: startTime,
            endTime: endTime,
            subject: item['title']?.toString() ?? '无标题',
            color: Colors.deepPurpleAccent,
          ));
        } catch (e) { print("解析失败: $e"); }
      }
      
      // 4. 仅通知日历数据变了，发生平滑刷新
      _dataSource.updateAppointments(appointments);
    }, onError: (err) {
      print('流错误: $err');
    });
  }

  @override
  void dispose() {
    // 退出页面时记得取消订阅
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的 Notion 日历')),
      // 移除 StreamBuilder，直接渲染 SfCalendar！
      body: SfCalendar(
        view: CalendarView.week,
        dataSource: _dataSource, // 使用固定的 dataSource
        allowDragAndDrop: true,
        onDragEnd: (details) {
          final dynamic app = details.appointment;
          if (app != null && details.droppingTime != null) {
            _updateEventTime(app.id, details.droppingTime!);
          }
        },
        timeSlotViewSettings: const TimeSlotViewSettings(timeFormat: 'HH:mm'),
      ),
    );
  }

  Future<void> _updateEventTime(dynamic id, DateTime newStartTime) async {
    try {
      await Supabase.instance.client.from('events').update({
        'start_time': newStartTime.toUtc().toIso8601String(),
        'end_time': newStartTime.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      }).eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已同步'), duration: Duration(milliseconds: 500))
        );
      }
    } catch (e) { print("更新失败: $e"); }
  }
}
// --- 5. 数据库视图 ---
class DatabaseViewWidget extends StatefulWidget {
  // 接收父组件传来的流
  final Stream<List<Map<String, dynamic>>> eventStream;
  const DatabaseViewWidget({super.key, required this.eventStream});
  
  @override
  State<DatabaseViewWidget> createState() => _DatabaseViewWidgetState();
}

class _DatabaseViewWidgetState extends State<DatabaseViewWidget> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('活动数据库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(context, null),
          )
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.eventStream, // 使用共享流
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('❌ 错误: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('暂无数据，点击右上角新建'));

          final events = snapshot.data!;
          
          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              final hasTime = event['start_time'] != null;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(event['title']?.toString() ?? '无标题活动', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    hasTime ? '开始: ${DateTime.parse(event['start_time']).toLocal().toString().substring(0, 16)}' : '📌 未排期 (收集箱)',
                    style: TextStyle(color: hasTime ? Colors.grey[700] : Colors.orange),
                  ),
                  trailing: const Icon(Icons.edit_note),
                  onTap: () => _showEditDialog(context, event),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic>? existingEvent) {
    final titleController = TextEditingController(text: existingEvent?['title'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existingEvent == null ? '新建活动' : '编辑活动'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '活动标题'),
              ),
              const SizedBox(height: 16),
              const Text('未来这里可以添加:'),
              const Text('- 开始/结束时间选择器', style: TextStyle(color: Colors.grey)),
              const Text('- 动态添加的自定义属性', style: TextStyle(color: Colors.grey)),
              const Text('- 单次/重复任务配置', style: TextStyle(color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                
                final payload = {
                  'title': title,
                };

                if (existingEvent == null) {
                  await Supabase.instance.client.from('events').insert(payload);
                } else {
                  await Supabase.instance.client.from('events').update(payload).eq('id', existingEvent['id']);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            )
          ],
        );
      },
    );
  }
}

// --- 6. 日历数据源类 ---
class _EventDataSource extends CalendarDataSource {
  _EventDataSource(List<Appointment> source) {
    appointments = source;
  }

  // 关键！新增一个更新方法，让内部通知日历平滑重绘，而不是销毁重建
  void updateAppointments(List<Appointment> newAppointments) {
    appointments = newAppointments;
    notifyListeners(CalendarDataSourceAction.reset, newAppointments);
  }
}