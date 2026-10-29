import 'package:flutter/material.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

/// Fixed-width column header corner showing track count and toggle button.
class MidiTracksHeaderCorner extends StatelessWidget {
  const MidiTracksHeaderCorner({
    super.key,
    required this.activeCount,
    required this.usedCount,
    required this.showAllChannels,
    required this.onToggleShowAllChannels,
  });

  final int activeCount;
  final int usedCount;
  final bool showAllChannels;
  final VoidCallback onToggleShowAllChannels;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181B24),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.tune_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            'TRACKS ($activeCount)',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onToggleShowAllChannels,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  fontSize: 9,
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
    required this.onOpenFxRack,
    this.trackHeight = 72.0,
  });

  final int chIndex;
  final MidiChannelState chState;
  final String instrumentName;
  final bool isActive;
  final VoidCallback onMuteToggled;
  final VoidCallback onSoloToggled;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onOpenInstrumentPicker;
  final VoidCallback onOpenFxRack;
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
    final hasVst3Synth = chState.vst3Instrument != null;
    final hasOverride = chState.presetOverride != null || hasVst3Synth;
    final hasFx = _hasActiveFx;

    return Container(
      height: trackHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chState.isMuted
            ? const Color(0xFF14161E)
            : (isActive ? const Color(0xFF222838) : const Color(0xFF1A1D27)),
        border: Border(
          bottom: const BorderSide(color: Colors.white10, width: 1),
          left: BorderSide(
            color: isActive
                ? const Color(0xFF00E5FF)
                : (hasVst3Synth
                      ? const Color(0xFF69F0AE)
                      : (hasOverride
                            ? const Color(0xFF6C63FF)
                            : (chState.isSolo
                                  ? Colors.amberAccent
                                  : Colors.transparent))),
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: LED, CH Name, VST3/MOD chip, 1-click VST3 GUI, FX, Mute, Solo
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
              if (hasVst3Synth) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF69F0AE).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: const Color(0xFF69F0AE),
                      width: 0.6,
                    ),
                  ),
                  child: const Text(
                    'VST3',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF69F0AE),
                    ),
                  ),
                ),
                if (chState.vst3Instrument!.hasEditor) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Open VST3 Synth Editor Window',
                    child: InkWell(
                      onTap: () {
                        chState.vst3Instrument!.openEditorWindow(
                          title:
                              'Ch ${chIndex + 1} — ${chState.vst3InstrumentName ?? "VST3 Synth"}',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'GUI',
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ] else if (hasOverride) ...[
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
              // FX / VST3 Insert Rack Button
              Tooltip(
                message: 'Channel ${chIndex + 1} FX & VST3 Effect Inserts',
                child: InkWell(
                  onTap: onOpenFxRack,
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
          // Middle Row: Instrument Button
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onOpenInstrumentPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: hasVst3Synth
                    ? const Color(0xFF69F0AE).withValues(alpha: 0.12)
                    : (hasOverride
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: hasVst3Synth
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
                      : (hasOverride
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                            : Colors.white10),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  if (hasVst3Synth) ...[
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
                        color: hasVst3Synth
                            ? const Color(0xFF69F0AE)
                            : (hasOverride
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white.withValues(alpha: 0.9)),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.tune,
                    size: 11,
                    color: hasVst3Synth
                        ? const Color(0xFF69F0AE)
                        : (hasOverride
                              ? const Color(0xFF00E5FF)
                              : Colors.white38),
                  ),
                ],
              ),
            ),
          ),
          // Bottom Row: Compact Volume Slider
          SizedBox(
            height: 18,
            child: Row(
              children: [
                const Icon(Icons.volume_down, size: 10, color: Colors.white38),
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
                    ),
                    child: Slider(
                      value: chState.volume,
                      onChanged: onVolumeChanged,
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
