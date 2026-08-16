import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A rotary knob widget for adjusting audio filter parameters with smooth drag interaction.
class RotaryKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
  final ValueChanged<double> onChanged;
  final double size;
  final bool enabled;

  const RotaryKnob({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
    required this.onChanged,
    this.size = 46.0,
    this.enabled = true,
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob> {
  double? _dragStartY;
  double? _dragStartValue;

  double get _normalizedValue =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  String get _formattedValue {
    if (widget.unit == 'Hz') {
      if (widget.value >= 1000) {
        return '${(widget.value / 1000).toStringAsFixed(1)}k';
      }
      return widget.value.toStringAsFixed(0);
    }
    if (widget.unit == 's') {
      if (widget.value < 1.0) {
        return '${(widget.value * 1000).toStringAsFixed(0)}ms';
      }
      return '${widget.value.toStringAsFixed(2)}s';
    }
    if (widget.unit == '%') {
      return '${(widget.value * 100).toStringAsFixed(0)}%';
    }
    if (widget.unit == 'x') {
      return '${widget.value.toStringAsFixed(1)}x';
    }
    if (widget.max <= 10.0 && widget.min >= -2.0) {
      return widget.value.toStringAsFixed(2);
    }
    return widget.value.toStringAsFixed(1);
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = widget.value;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _dragStartY == null || _dragStartValue == null) return;

    final dy = _dragStartY! - details.globalPosition.dy;
    final range = widget.max - widget.min;
    // 150 pixels of drag travels the entire range
    final deltaValue = (dy / 150.0) * range;
    final newValue = (_dragStartValue! + deltaValue).clamp(widget.min, widget.max);
    widget.onChanged(newValue);
  }

  void _onDoubleTap() {
    if (!widget.enabled) return;
    widget.onChanged(widget.defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.35,
      child: GestureDetector(
        onVerticalDragStart: widget.enabled ? _onPanStart : null,
        onVerticalDragUpdate: widget.enabled ? _onPanUpdate : null,
        onDoubleTap: widget.enabled ? _onDoubleTap : null,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: widget.enabled
              ? '${widget.label}: $_formattedValue (Double-tap to reset)'
              : '${widget.label}: Disabled for this target',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _KnobPainter(
                    normalizedValue: _normalizedValue,
                    primaryColor: theme.colorScheme.primary,
                    trackColor: theme.colorScheme.surfaceContainerHighest,
                    knobColor: theme.colorScheme.surfaceContainerHigh,
                    pointerColor: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formattedValue,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double normalizedValue;
  final Color primaryColor;
  final Color trackColor;
  final Color knobColor;
  final Color pointerColor;

  static const double _startAngle = 0.75 * math.pi; // ~135 degrees
  static const double _sweepAngle = 1.5 * math.pi; // 270 degrees total sweep

  _KnobPainter({
    required this.normalizedValue,
    required this.primaryColor,
    required this.trackColor,
    required this.knobColor,
    required this.pointerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = (size.width / 14.0).clamp(2.0, 3.5);
    final inset = strokeWidth + 1.0;

    // Track arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - inset),
      _startAngle,
      _sweepAngle,
      false,
      trackPaint,
    );

    // Active arc
    final activePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 0.5
      ..strokeCap = StrokeCap.round;

    final currentSweep = _sweepAngle * normalizedValue;
    if (currentSweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - inset),
        _startAngle,
        currentSweep,
        false,
        activePaint,
      );
    }

    // Knob circular body
    final bodyRadius = (radius - inset - 3).clamp(3.0, radius);
    final bodyPaint = Paint()
      ..color = knobColor
      ..style = PaintingStyle.fill;

    final bodyShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawCircle(center, bodyRadius, bodyShadow);
    canvas.drawCircle(center, bodyRadius, bodyPaint);

    // Pointer tick
    final pointerAngle = _startAngle + currentSweep;
    final pointerDistance = (bodyRadius - 3.0).clamp(1.0, bodyRadius);
    final pointerPos = Offset(
      center.dx + pointerDistance * math.cos(pointerAngle),
      center.dy + pointerDistance * math.sin(pointerAngle),
    );

    final pointerPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(pointerPos, (strokeWidth * 0.7).clamp(1.5, 2.5), pointerPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}
