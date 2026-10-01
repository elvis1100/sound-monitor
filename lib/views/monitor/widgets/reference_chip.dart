import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../models/sound_reference.dart';
import '../../../theme.dart';
import 'reference_guide_sheet.dart';

class ReferenceChip extends ConsumerWidget {
  const ReferenceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(monitorControllerProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final reference = reading.hasLiveReading
        ? closestSoundReference(reading.currentDb)
        : null;
    final accent = reading.hasLiveReading
        ? colors.levelAccent(reading.currentDb)
        : Theme.of(context).colorScheme.primary;
    final label = reference == null
        ? 'Sound reference'
        : '≈ ${reference.db} dB(A) · ${reference.description}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: accent.withValues(alpha: 0.10),
          shape: StadiumBorder(
            side: BorderSide(color: accent.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showReferenceGuide(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
