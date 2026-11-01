import 'package:flutter/material.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

/// Fixed-width column header corner showing track count, global VST3 & FX buttons, toggle button, and global volume slider.
class MidiTracksHeaderCorner extends StatelessWidget {
  const MidiTracksHeaderCorner({
    super.key,
    required this.activeCount,
    required this.usedCount,
    required this.showAllChannels,
    required this.onToggleShowAllChannels,
    required this.hasGlobalVst3,
    required this.onOpenGlobalVst3Picker,
    required this.hasGlobalFx,
    required this.onOpenGlobalFxRack,
    required this.masterVolume,
    required this.onMasterVolumeChanged,
  });

  final int activeCount;
  final int usedCount;
  final bool showAllChannels;
  final VoidCallback onToggleShowAllChannels;
  final bool hasGlobalVst3;
  final VoidCallback onOpenGlobalVst3Picker;
  final bool hasGlobalFx;
  final VoidCallback onOpenGlobalFxRack;
  final double masterVolume;
  final ValueChanged<double> onMasterVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181B24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: TRACKS (N), VST, FX, Used (N) / All 16
          SizedBox(
            height: 20,
            child: Row(
              children: [
                const Icon(
                  Icons.tune_outlined,
                  size: 13,
                  color: Colors.white54,
                ),
                const SizedBox(width: 4),
                Text(
                  'TRACKS ($activeCount)',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Multi-Timbral VST3 Instrument for All 16 Channels',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onOpenGlobalVst3Picker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: hasGlobalVst3
                            ? const Color(0xFF69F0AE).withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: hasGlobalVst3
                              ? const Color(0xFF69F0AE)
                              : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'VST',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: hasGlobalVst3
                              ? const Color(0xFF69F0AE)
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      'Global Master FX & VST3 Effect Inserts (All Channels)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onOpenGlobalFxRack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: hasGlobalFx
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: hasGlobalFx
                              ? const Color(0xFF00E5FF)
                              : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'FX',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: hasGlobalFx
                              ? const Color(0xFF00E5FF)
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onToggleShowAllChannels,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: showAllChannels
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.25)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: showAllChannels
                            ? const Color(0xFF6C63FF)
                            : Colors.white24,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      showAllChannels ? 'Used ($usedCount)' : 'All 16',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: showAllChannels
                            ? const Color(0xFF00E5FF)
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Row 2: Global Master Volume Slider
          SizedBox(
            height: 18,
            child: Row(
              children: [
                Tooltip(
                  message: 'Reset master volume to 100%',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => onMasterVolumeChanged(1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        masterVolume == 0
                            ? Icons.volume_off
                            : (masterVolume < 0.5
                                  ? Icons.volume_down
                                  : Icons.volume_up),
                        size: 12,
                        color: masterVolume > 0
                            ? const Color(0xFF00E5FF)
                            : Colors.white38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const Text(
                  'VOL',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white54,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 7,
                      ),
                      activeTrackColor: const Color(0xFF00E5FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: masterVolume.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: onMasterVolumeChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${(masterVolume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
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

/// Header card for a single MIDI channel lane in the DAW tracks column.
class MidiTrackHeader extends StatelessWidget {
  const MidiTrackHeader({
    super.key,
    required this.chIndex,
    required this.chState,
    required this.instrumentName,
    required this.isActive,
    required this.onMuteToggled,
    required this.onSoloToggled,
    required this.onVolumeChanged,
    required this.onOpenInstrumentPicker,
    required this.onOpenVst3InstrumentPicker,
    required this.onOpenFxRack,
    this.isSelected = false,
    this.onSelect,
    this.masterVolume = 1.0,
    this.trackHeight = 72.0,
  });

  final int chIndex;
  final MidiChannelState chState;
  final String instrumentName;
  final bool isActive;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback onMuteToggled;
  final VoidCallback onSoloToggled;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onOpenInstrumentPicker;
  final VoidCallback onOpenVst3InstrumentPicker;
  final VoidCallback onOpenFxRack;
  final double masterVolume;
  final double trackHeight;

  bool get _hasActiveFx {
    final bus = chState.bus;
    if (bus == null) return false;
    for (final type in SoundFontFilterType.values) {
      if (chState.filterRack.isActive(type)) return true;
    }
    for (var i = 0; i < 8; i++) {
      if (SoundFontVst3Manager.instance.getBusEffect(bus, i) != null) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDrums = chIndex == 9;
    final hasChannelVst3 = chState.vst3Instrument != null;
    final hasEffectiveVst3 = chState.effectiveVst3Instrument != null;
    final hasOverride = chState.presetOverride != null;
    final hasFx = _hasActiveFx;

    return InkWell(
      onTap: onSelect,
      child: Container(
        height: trackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chState.isMuted
              ? (isSelected ? const Color(0xFF1E2230) : const Color(0xFF14161E))
              : (isSelected
                    ? const Color(0xFF262E40)
                    : (isActive
                          ? const Color(0xFF222838)
                          : const Color(0xFF1A1D27))),
          border: Border(
            bottom: const BorderSide(color: Colors.white10, width: 1),
            left: BorderSide(
              color: isSelected
                  ? const Color(0xFF00E5FF)
                  : (isActive
                        ? const Color(0xFF00E5FF)
                        : (hasEffectiveVst3
                              ? const Color(0xFF69F0AE)
                              : (hasOverride
                                    ? const Color(0xFF6C63FF)
                                    : (chState.isSolo
                                          ? Colors.amberAccent
                                          : Colors.transparent)))),
              width: isSelected ? 4 : 3,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: LED, CH Name, PIANO chip, MOD chip, VST button, FX button, Mute, Solo
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? const Color(0xFF00E5FF)
                        : (chState.isMuted ? Colors.red : Colors.white24),
                    boxShadow: isActive
                        ? [
                            const BoxShadow(
                              color: Color(0xFF00E5FF),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'CH ${chIndex + 1}${isDrums ? " 🥁" : ""}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: isDrums ? Colors.orangeAccent : Colors.white,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Active channel for piano keyboard input',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: const Color(0xFF00E5FF),
                          width: 0.6,
                        ),
                      ),
                      child: const Text(
                        'PIANO',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                  ),
                ],
                if (hasOverride && !hasChannelVst3) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'MOD',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // VST3 Virtual Instrument Button
                Tooltip(
                  message: 'Channel ${chIndex + 1} VST3 Virtual Instrument',
                  child: InkWell(
                    onTap: () {
                      onSelect?.call();
                      onOpenVst3InstrumentPicker();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: hasChannelVst3
                            ? const Color(0xFF69F0AE).withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(3),
                        border: hasChannelVst3
                            ? Border.all(
                                color: const Color(0xFF69F0AE),
                                width: 0.8,
                              )
                            : null,
                      ),
                      child: Text(
                        'VST',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: hasChannelVst3
                              ? const Color(0xFF69F0AE)
                              : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // FX / VST3 Insert Rack Button
                Tooltip(
                  message: 'Channel ${chIndex + 1} FX & VST3 Effect Inserts',
                  child: InkWell(
                    onTap: () {
                      onSelect?.call();
                      onOpenFxRack();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: hasFx
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(3),
                        border: hasFx
                            ? Border.all(
                                color: const Color(0xFF00E5FF),
                                width: 0.8,
                              )
                            : null,
                      ),
                      child: Text(
                        'FX',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: hasFx
                              ? const Color(0xFF00E5FF)
                              : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Mute Button
                InkWell(
                  onTap: onMuteToggled,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: chState.isMuted ? Colors.red : Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'M',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: chState.isMuted ? Colors.white : Colors.white60,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Solo Button
                InkWell(
                  onTap: onSoloToggled,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: chState.isSolo ? Colors.amber : Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'S',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: chState.isSolo ? Colors.black : Colors.white60,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // Middle Row: Instrument Display & Tune Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: hasEffectiveVst3
                    ? const Color(0xFF69F0AE).withValues(alpha: 0.12)
                    : (hasOverride
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: hasEffectiveVst3
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
                      : (hasOverride
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                            : Colors.white10),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  if (hasEffectiveVst3) ...[
                    const Icon(
                      Icons.extension,
                      size: 10,
                      color: Color(0xFF69F0AE),
                    ),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(
                      instrumentName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: hasEffectiveVst3
                            ? const Color(0xFF69F0AE)
                            : (hasOverride
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white.withValues(alpha: 0.9)),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      onSelect?.call();
                      onOpenInstrumentPicker();
                    },
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(
                        Icons.tune,
                        size: 11,
                        color: hasEffectiveVst3
                            ? const Color(0xFF69F0AE)
                            : (hasOverride
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white60),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Row: Compact Volume Slider multiplied by masterVolume for effective feedback
            SizedBox(
              height: 18,
              child: () {
                final displayVolume = (chState.volume * masterVolume).clamp(
                  0.0,
                  1.0,
                );
                return Row(
                  children: [
                    Tooltip(
                      message:
                          'Channel ${chIndex + 1} Volume: ${(displayVolume * 100).round()}% (base: ${(chState.volume * 100).round()}%, master: ${(masterVolume * 100).round()}%)',
                      child: Icon(
                        displayVolume == 0
                            ? Icons.volume_off
                            : (displayVolume < 0.5
                                  ? Icons.volume_down
                                  : Icons.volume_up),
                        size: 10,
                        color: displayVolume > 0
                            ? Colors.white60
                            : Colors.white24,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 6,
                          ),
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: displayVolume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (newDisplayVal) {
                            final newChVol = masterVolume > 0
                                ? (newDisplayVal / masterVolume).clamp(0.0, 1.0)
                                : newDisplayVal;
                            onVolumeChanged(newChVol);
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${(displayVolume * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 8,
                          fontFamily: 'monospace',
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                );
              }(),
            ),
          ],
        ),
      ),
    );
  }
}
