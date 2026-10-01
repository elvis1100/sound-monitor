import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'views/monitor/monitor_view.dart';

void main() {
  runApp(const ProviderScope(child: SoundMonitorApp()));
}

class SoundMonitorApp extends ConsumerWidget {
  const SoundMonitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Sound Level Monitor',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MonitorView(),
    );
  }
}
