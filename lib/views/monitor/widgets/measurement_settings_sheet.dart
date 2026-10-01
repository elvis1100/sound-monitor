import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../models/measurement_settings.dart';
import '../../../theme.dart';

typedef FrequencySelection = Future<void> Function(FrequencyWeighting value);
typedef TimeSelection = Future<void> Function(TimeResponse value);

class MeasurementSettingsSheet extends ConsumerWidget {
  final FrequencySelection onFrequencySelected;
  final TimeSelection onTimeSelected;

  const MeasurementSettingsSheet({
    super.key,
    required this.onFrequencySelected,
    required this.onTimeSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monitorControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Meter settings', style: textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close settings',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Frequency weighting', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final weighting in FrequencyWeighting.values)
                  ChoiceChip(
                    label: Text(weighting.unit),
                    selected: state.frequencyWeighting == weighting,
                    onSelected: (_) => onFrequencySelected(weighting),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Time response', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final response in TimeResponse.values)
                  ChoiceChip(
                    label: Text(response.label),
                    selected: state.timeResponse == response,
                    onSelected: (_) => onTimeSelected(response),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Changing weighting or response restarts MIN/MAX and the graph. The timer keeps running. Medium is a custom response.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Theme', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final mode in [ThemeMode.dark, ThemeMode.light])
                  ChoiceChip(
                    label: Text(mode == ThemeMode.dark ? 'Dark' : 'Light'),
                    selected: themeMode == mode,
                    onSelected: (_) =>
                        ref.read(themeModeProvider.notifier).setMode(mode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
