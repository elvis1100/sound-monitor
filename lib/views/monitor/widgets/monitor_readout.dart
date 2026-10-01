import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import 'meter_arc.dart';

class MonitorReadout extends ConsumerWidget {
  const MonitorReadout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(monitorControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final value = reading.hasLiveReading
        ? reading.currentDb.toStringAsFixed(1)
        : '—';
    return Semantics(
      label: reading.hasSamples
          ? 'Current $value ${reading.frequencyWeighting.unit}, '
                'minimum ${reading.minDb.toStringAsFixed(1)}, '
                'maximum ${reading.maxDb.toStringAsFixed(1)}, '
                'average ${reading.avgDb.toStringAsFixed(1)}'
          : 'Ready to measure',
      child: Column(
        children: [
          MeterArc(
            level: reading.currentDb,
            minLevel: reading.minDb,
            maxLevel: reading.maxDb,
            averageLevel: reading.avgDb,
            hasReading: reading.hasSamples,
            hasCurrent: reading.hasLiveReading,
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 64,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 5, bottom: 5),
                  child: Text(
                    reading.frequencyWeighting.unit,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
