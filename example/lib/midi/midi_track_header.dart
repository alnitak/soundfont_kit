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
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    final isDrums = chIndex == 9;
    final hasOverride = chState.presetOverride != null;

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
                : (hasOverride
                      ? const Color(0xFF6C63FF)
                      : (chState.isSolo
                            ? Colors.amberAccent
                            : Colors.transparent)),
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: LED, CH Name, CUSTOM chip, Mute, Solo
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
              if (hasOverride) ...[
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
                color: hasOverride
                    ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: hasOverride
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                      : Colors.white10,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      instrumentName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: hasOverride
                            ? const Color(0xFF00E5FF)
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.tune,
                    size: 11,
                    color: hasOverride
                        ? const Color(0xFF00E5FF)
                        : Colors.white38,
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
