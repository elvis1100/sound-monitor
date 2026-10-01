import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../models/calibration_profile.dart';

Future<void> showCalibrationSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CalibrationSheet(),
    );

class CalibrationSheet extends ConsumerStatefulWidget {
  const CalibrationSheet({super.key});

  @override
  ConsumerState<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends ConsumerState<CalibrationSheet> {
  double _adjustmentDb = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(monitorControllerProvider).calibration;
    if (profile?.source == CalibrationSource.manual) {
      _adjustmentDb = profile!.adjustmentDb;
    }
  }

  void _adjust(double amount) => setState(() {
    _adjustmentDb = ((_adjustmentDb * 10).round() + (amount * 10).round()) / 10;
    _adjustmentDb = _adjustmentDb.clamp(-30.0, 30.0);
  });

  Future<void> _save() async {
    setState(() => _submitting = true);
    await ref
        .read(monitorControllerProvider.notifier)
        .setManualAdjustment(_adjustmentDb);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ref.read(monitorControllerProvider).errorMessage == null) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _reset() async {
    setState(() => _submitting = true);
    await ref.read(monitorControllerProvider.notifier).resetCalibration();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ref.read(monitorControllerProvider).errorMessage == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(monitorControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final unit = reading.frequencyWeighting.unit;
    final canDecrease = !_submitting && _adjustmentDb > -30;
    final canIncrease = !_submitting && _adjustmentDb < 30;
    final estimate = reading.rawDbFs + CalibrationProfile.nominalOffsetDb;
    final preview = (estimate + _adjustmentDb).clamp(0.0, 140.0);
    final signedOffset =
        '${_adjustmentDb >= 0 ? '+' : ''}${_adjustmentDb.toStringAsFixed(1)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calibrate microphone',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Adjust the displayed estimate for this microphone and weighting. '
              'The offset starts at +0.0 dB and can be changed in 0.1 or 1 dB steps.',
            ),
            const SizedBox(height: 22),
            Center(
              child: Column(
                children: [
                  Text(
                    'ADDED TO ESTIMATE',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.outlined(
                        tooltip: 'Decrease offset by 1 dB',
                        icon: const Icon(Icons.remove),
                        onPressed: canDecrease ? () => _adjust(-1) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          label: 'Added offset $signedOffset decibels',
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$signedOffset dB',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.outlined(
                        tooltip: 'Increase offset by 1 dB',
                        icon: const Icon(Icons.add),
                        onPressed: canIncrease ? () => _adjust(1) : null,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: canDecrease ? () => _adjust(-0.1) : null,
                        child: const Text('−0.1'),
                      ),
                      const SizedBox(width: 24),
                      TextButton(
                        onPressed: canIncrease ? () => _adjust(0.1) : null,
                        child: const Text('+0.1'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reading.hasLiveReading
                  ? 'Preview: ${preview.toStringAsFixed(1)} $unit'
                  : 'Preview: — $unit',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (!reading.isRecording)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Start monitoring before saving an offset.'),
              ),
            if (reading.calibration?.source == CalibrationSource.reference)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Saving a manual offset replaces the existing reference calibration.',
                ),
              ),
            if (reading.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  reading.errorMessage!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'A manual offset does not verify absolute accuracy. Range: −30.0 to +30.0 dB.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (reading.calibration != null)
                  TextButton(
                    onPressed: _submitting ? null : _reset,
                    child: const Text('Reset offset'),
                  ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _submitting || !reading.canCalibrate
                      ? null
                      : _save,
                  child: const Text('Save offset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
