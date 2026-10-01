import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../theme.dart';

import '../../../models/sound_reference.dart';

class ReferenceGuideSheet extends ConsumerWidget {
  final ScrollController? scrollController;

  const ReferenceGuideSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppColors>()!;
    final reading = ref.watch(monitorControllerProvider);
    final currentExample = reading.hasLiveReading
        ? closestSoundReference(reading.currentDb)
        : null;
    final examples = soundReferences.reversed.toList(growable: false);
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sound reference',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close sound reference',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              'Approximate A-weighted examples. They do not verify this phone’s reading.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: examples.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final example = examples[index];
                  final accent = colors.levelAccent(example.db.toDouble());
                  final selected = currentExample?.db == example.db;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.18),
                        child: Text(
                          '${example.db}',
                          style: TextStyle(color: accent),
                        ),
                      ),
                      title: Text(example.description),
                      trailing: Text(
                        'dB(A)',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showReferenceGuide(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) =>
            ReferenceGuideSheet(scrollController: controller),
      ),
    );
