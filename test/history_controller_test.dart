import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/controllers/history_controller.dart';
import 'package:sound_level_monitor/models/session_model.dart';
import 'package:sound_level_monitor/services/database_service.dart';

class FakeHistoryDatabase extends DatabaseService {
  final List<SessionModel> rows;
  bool failNextPage = false;

  FakeHistoryDatabase(this.rows);

  @override
  Future<List<SessionModel>> getSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    if (offset > 0 && failNextPage) {
      throw StateError('Temporary database failure');
    }
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<bool> deleteSession(int id) async {
    final before = rows.length;
    rows.removeWhere((row) => row.id == id);
    return rows.length != before;
  }
}

SessionModel session(int id) => SessionModel(
  id: id,
  title: 'Session $id',
  date: DateTime.utc(2026, 9, 30),
  minDb: 40,
  avgDb: 50,
  maxDb: 60,
  durationSeconds: 10,
);

void main() {
  test(
    'pagination failure preserves loaded history and retry completes it',
    () async {
      final database = FakeHistoryDatabase(
        List.generate(55, (index) => session(index + 1)),
      );
      final container = ProviderContainer(
        overrides: [databaseServiceProvider.overrideWithValue(database)],
      );
      final listener = container.listen(historyControllerProvider, (_, _) {});
      addTearDown(() {
        listener.close();
        container.dispose();
      });

      final controller = container.read(historyControllerProvider.notifier);
      await controller.loadFirstPage();
      expect(container.read(historyControllerProvider).sessions, hasLength(50));

      database.failNextPage = true;
      await controller.loadMore();
      final failed = container.read(historyControllerProvider);
      expect(failed.sessions, hasLength(50));
      expect(failed.moreError, contains('Could not load more'));

      database.failNextPage = false;
      await controller.loadMore();
      final recovered = container.read(historyControllerProvider);
      expect(recovered.sessions, hasLength(55));
      expect(recovered.hasMore, isFalse);
      expect(recovered.moreError, isNull);

      expect(await controller.deleteSession(1), isTrue);
      expect(container.read(historyControllerProvider).sessions.first.id, 2);
    },
  );
}
