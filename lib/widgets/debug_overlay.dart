import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  static const MethodChannel _ch = MethodChannel('debug.metrics');
  Timer? _timer;
  double _cpu = 0.0; // app CPU %
  double _mem = 0.0; // device used %
  double _gpu = 0.0; // approximated from raster times
  final List<double> _rasterMs = <double>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _sampleMetrics();
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final double raster = t.rasterDuration.inMicroseconds / 1000.0; // ms
      _rasterMs.add(raster);
      if (_rasterMs.length > 60) {
        _rasterMs.removeAt(0);
      }
    }
    final avg = _rasterMs.isEmpty
        ? 0.0
        : _rasterMs.reduce((a, b) => a + b) / _rasterMs.length;
    _gpu = (avg / 16.67 * 100.0).clamp(0.0, 100.0);
  }

  Future<void> _sampleMetrics() async {
    try {
      final map = await _ch.invokeMethod<dynamic>('sample') as Map<dynamic, dynamic>;
      _cpu = (map['cpuAppPct'] as num?)?.toDouble() ?? 0.0;
      _mem = (map['memUsedPct'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'CPU ${_cpu.toStringAsFixed(0)}% | GPU ${_gpu.toStringAsFixed(0)}% | MEM ${_mem.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

