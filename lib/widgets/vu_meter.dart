import 'dart:async';
import 'package:flutter/material.dart';

// PERF: throttle to ~30 Hz to avoid jank
class _ThrottleStreamTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration interval;
  _ThrottleStreamTransformer(this.interval);
  @override
  Stream<T> bind(Stream<T> stream) async* {
    T? last;
    T? lastEmitted;
    final controller = StreamController<T>();
    Timer? timer;
    void tick() {
      if (last != null) {
        // PERF: basic distinct before emitting
        if (identical(last, lastEmitted)) {
          // skip
        } else {
          controller.add(last as T);
          lastEmitted = last;
        }
      }
      timer = null;
    }
    final sub = stream.listen((event) {
      last = event;
      timer ??= Timer(interval, tick); // ~30 Hz sampleTime
    }, onError: controller.addError, onDone: controller.close);
    yield* controller.stream;
    await sub.cancel();
    timer?.cancel();
  }
}

class VUMeter extends StatelessWidget {
  final Stream<double> stream; // 0..1
  final double? threshold; // optional 0..1
  final double height;
  const VUMeter({super.key, required this.stream, this.threshold, this.height = 14});

  @override
  Widget build(BuildContext context) {
    final throttled = stream.transform(_ThrottleStreamTransformer<double>(const Duration(milliseconds: 33)));
    return RepaintBoundary(
      child: SizedBox(
        height: height + 12,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return StreamBuilder<double>(
              stream: throttled,
              initialData: 0.0,
              builder: (context, snap) {
                final v = (snap.data ?? 0.0).clamp(0.0, 1.0);
                return CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _VUPainter(v, threshold),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _VUPainter extends CustomPainter {
  final double level; // 0..1
  final double? threshold; // 0..1
  _VUPainter(this.level, this.threshold);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0x22000000);
    final fg = Paint()..color = Colors.green;
    final th = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(6));
    canvas.drawRRect(r, bg);
    final w = (level * size.width).clamp(0.0, size.width);
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), const Radius.circular(6));
    canvas.drawRRect(rr, fg);
    if (threshold != null) {
      final x = (threshold!.clamp(0.0, 1.0)) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), th);
    }
  }

  @override
  bool shouldRepaint(covariant _VUPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.threshold != threshold;
  }
}
