import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

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
      home: const CalendarScreen(),
    );
  }
}

// --- 3. 日历主界面 ---
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Stream<List<Map<String, dynamic>>> _eventStream =
      Supabase.instance.client.from('events').stream(primaryKey: ['id']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的 Notion 日历')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _eventStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('❌ 错误: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final List<Appointment> appointments = [];
          if (snapshot.hasData) {
            for (var data in snapshot.data!) {
              try {
                final DateTime startTime = DateTime.parse(data['start_time'].toString()).toLocal();
                final DateTime endTime = data['end_time'] != null 
                    ? DateTime.parse(data['end_time'].toString()).toLocal() 
                    : startTime.add(const Duration(hours: 1));

                appointments.add(Appointment(
                  id: data['id'],
                  startTime: startTime,
                  endTime: endTime,
                  subject: data['title']?.toString() ?? '无标题',
                  color: Colors.deepPurpleAccent,
                ));
              } catch (e) { print("解析失败: $e"); }
            }
          }

          return SfCalendar(
            view: CalendarView.week,
            dataSource: _EventDataSource(appointments),
            allowDragAndDrop: true,
            onDragEnd: (details) {
              final dynamic app = details.appointment;
              if (app != null && details.droppingTime != null) {
                _updateEventTime(app.id, details.droppingTime!);
              }
            },
            timeSlotViewSettings: const TimeSlotViewSettings(timeFormat: 'HH:mm'),
          );
        },
      ),
    );
  } // <--- 这里是 build 的结束

  Future<void> _updateEventTime(dynamic id, DateTime newStartTime) async {
    try {
      await Supabase.instance.client.from('events').update({
        'start_time': newStartTime.toUtc().toIso8601String(),
        'end_time': newStartTime.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      }).eq('id', id).select();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已同步'), duration: Duration(milliseconds: 500)));
      }
    } catch (e) { print("更新失败: $e"); }
  }
} // <--- 关键！这是 _CalendarScreenState 的结束

// --- 4. 日历数据源类 (必须在 State 类外面) ---
class _EventDataSource extends CalendarDataSource {
  _EventDataSource(List<Appointment> source) {
    appointments = source;
  }
}