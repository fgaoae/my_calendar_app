import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/calendar_view.dart';
import 'screens/database_view.dart';
import 'theme/airy_theme.dart';

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
      theme: AiryTheme.themeData,
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
  bool _reverseSwitch = false;
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
    final pages = [
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
    ];

    return Scaffold(
      body: Stack(
        children: [
          _buildAnimatedPage(index: 0, child: pages[0]),
          _buildAnimatedPage(index: 1, child: pages[1]),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AiryPalette.border.withValues(alpha: 0.72)),
                gradient: LinearGradient(
                  colors: [
                    AiryPalette.panel.withValues(alpha: 0.92),
                    AiryPalette.panelTint.withValues(alpha: 0.94),
                  ],
                ),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onDestinationSelected,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.calendar_today), label: '日历'),
                  NavigationDestination(icon: Icon(Icons.table_chart), label: '数据库'),
                ],
              ),
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 420.ms, curve: Curves.easeOutCubic)
            .slideY(begin: 0.2, end: 0, duration: 420.ms, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _buildAnimatedPage({required int index, required Widget child}) {
    final active = _currentIndex == index;
    final awayOffset = _reverseSwitch ? const Offset(-0.03, 0) : const Offset(0.03, 0);
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: AiryTheme.medium,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: active ? Offset.zero : awayOffset,
          duration: AiryTheme.medium,
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _reverseSwitch = index < _currentIndex;
      _currentIndex = index;
    });
  }

  @override
  void dispose() {
    _syncTick.dispose();
    super.dispose();
  }
}
