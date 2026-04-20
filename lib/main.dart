import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/calendar_view.dart';
import 'screens/database_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cihxthzvavqueiwujcbe.supabase.co',
    // ⚠️ 改成你真实 anonKey
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpaHh0aHp2YXZxdWVpd3VqY2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNTU1MDEsImV4cCI6MjA5MTkzMTUwMX0.h9ZGVLzdF2rdlj6rtJ_xGuXugO6f4Rpc8IOmhv_mTLM',
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
  final ValueNotifier<int> _syncTick = ValueNotifier<int>(0);

  void _requestDataSync() {
    _syncTick.value++;
  }

  @override
  void initState() {
    super.initState();
    _sharedEventStream = Supabase.instance.client
        .from('events')
        .stream(primaryKey: ['id']);
    _sharedDbStream = Supabase.instance.client
        .from('databases')
        .stream(primaryKey: ['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CalendarViewWidget(
            eventStream: _sharedEventStream,
            dbStream: _sharedDbStream,
            syncTick: _syncTick,
            requestSync: _requestDataSync,
          ),
          DatabaseViewWidget(
            eventStream: _sharedEventStream,
            dbStream: _sharedDbStream,
            syncTick: _syncTick,
            requestSync: _requestDataSync,
          ),
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

  @override
  void dispose() {
    _syncTick.dispose();
    super.dispose();
  }
}
