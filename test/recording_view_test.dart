import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sound_level_monitor/services/playback_service.dart';
import 'package:sound_level_monitor/theme.dart';
import 'package:sound_level_monitor/views/recording/recording_view.dart';
import 'package:sound_level_monitor/views/history/history_view.dart';

import 'fake_playback_service.dart';

void main() {
  testWidgets(
    'compact recording screen supports playback, seek, rename, export, and share',
    (tester) async {
      final database = RecordingTestDatabase();
      final player = FakePlaybackService();
      addTearDown(player.stream.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(database),
            playbackServiceProvider.overrideWithValue(player),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const RecordingView(sessionId: 11),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample recording'), findsOneWidget);
      expect(find.text('Saved audio'), findsOneWidget);
      expect(find.text('48.6 dB(A) at 00:00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byIcon(Icons.play_arrow),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause recording playback'), findsOneWidget);
      await tester.tap(find.byTooltip('Forward 5 seconds'));
      await tester.pumpAndSettle();
      expect(player.seekTargets.last, 5000);
      expect(find.text('63.4 dB(C) at 00:05'), findsOneWidget);
      await tester.tap(find.byTooltip('Back 5 seconds'));
      await tester.pumpAndSettle();
      expect(player.seekTargets.last, 0);
      await tester.ensureVisible(find.byTooltip('Rename recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename recording'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My recording');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('My recording'), findsOneWidget);
      await tester.ensureVisible(find.text('Export WAV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export WAV'));
      await tester.pumpAndSettle();
      expect(player.exports.single.$2, 'My recording');
      await tester.ensureVisible(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(player.shares.single.$2, 'My recording');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recording screen remains usable on a narrow screen with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = RecordingTestDatabase();
      final player = FakePlaybackService();
      addTearDown(player.stream.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(database),
            playbackServiceProvider.overrideWithValue(player),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const RecordingView(sessionId: 11),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byIcon(Icons.play_arrow),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause recording playback'), findsOneWidget);
      await tester.ensureVisible(find.text('Export WAV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export WAV'));
      await tester.pumpAndSettle();
      expect(player.exports, hasLength(1));
      await tester.ensureVisible(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(player.shares, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'History opens a recording and deletion returns to refreshed History',
    (tester) async {
      final database = RecordingTestDatabase();
      final player = FakePlaybackService();
      addTearDown(player.stream.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(database),
            playbackServiceProvider.overrideWithValue(player),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HistoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample recording'));
      await tester.pumpAndSettle();
      expect(find.text('Saved audio'), findsOneWidget);
      await tester.ensureVisible(find.text('Delete recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('History'), findsOneWidget);
      expect(find.text('No saved sessions yet.'), findsOneWidget);
      expect(database.saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
