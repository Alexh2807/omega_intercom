import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

class AudioProcessorConfig {
  final int sampleRate;
  final int micLowCutHz;
  final int micHighCutHz;
  final double gateNorm; // 0..1
  final bool echoEnabled;
  final double echoStrength; // 0..1
  final int echoThreshold; // avg |amp|
  final double micGain;
  const AudioProcessorConfig({
    required this.sampleRate,
    required this.micLowCutHz,
    required this.micHighCutHz,
    required this.gateNorm,
    required this.echoEnabled,
    required this.echoStrength,
    required this.echoThreshold,
    required this.micGain,
  });

  Map<String, dynamic> toMap() => {
        'sr': sampleRate,
        'lchz': micLowCutHz,
        'hchz': micHighCutHz,
        'gate': gateNorm,
        'echoE': echoEnabled,
        'echoS': echoStrength,
        'echoT': echoThreshold,
        'mg': micGain,
      };
}

class ProcResult {
  final Uint8List pcm; // processed (or empty if gated)
  final double micLevel; // 0..1
  ProcResult(this.pcm, this.micLevel);
}

class AudioProcessor {
  Isolate? _iso;
  SendPort? _send;
  int _nextId = 1;
  final Map<int, Completer<ProcResult?>> _pending = {};

  Future<void> start(AudioProcessorConfig cfg) async {
    if (_iso != null) return;
    final recv = ReceivePort();
    _iso = await Isolate.spawn(_entry, recv.sendPort, debugName: 'AudioProcessor');
    _send = await recv.first as SendPort;
    final ctrl = ReceivePort();
    _send!.send(['init', cfg.toMap(), ctrl.sendPort]);
    await ctrl.first; // ack
  }

  Future<void> update(AudioProcessorConfig cfg) async {
    final sp = _send;
    if (sp == null) return;
    sp.send(['cfg', cfg.toMap()]);
  }

  Future<ProcResult?> process(Uint8List chunk, double rxEma) async {
    final sp = _send;
    if (sp == null) return null;
    final id = _nextId++;
    final c = Completer<ProcResult?>();
    _pending[id] = c;
    final rp = ReceivePort();
    sp.send(['proc', id, chunk, rxEma, rp.sendPort]);
    rp.listen((msg) {
      if (msg is List && msg.length == 3 && msg[0] == id) {
        final ok = msg[1] as bool;
        if (!ok) {
          c.complete(null);
        } else {
          c.complete(ProcResult(msg[2] as Uint8List, _computeLevel(msg[2] as Uint8List)));
        }
        rp.close();
        _pending.remove(id);
      }
    });
    return c.future;
  }

  double _computeLevel(Uint8List pcm) {
    try {
      final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
      int count = 0; int sum = 0;
      for (int i = 0; i < pcm.lengthInBytes; i += 2) { int s = bd.getInt16(i, Endian.little); if (s < 0) s = -s; sum += s; count++; }
      if (count == 0) return 0.0;
      return (sum / count) / 32768.0;
    } catch (_) { return 0.0; }
  }

  void stop() {
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _send = null;
    for (final c in _pending.values) { if (!c.isCompleted) c.complete(null); }
    _pending.clear();
  }

  static void _entry(SendPort initPort) {
    final ctrl = ReceivePort();
    initPort.send(ctrl.sendPort);
    _Biquad? fHP; _Biquad? fLP;
    int sr = 16000;
    double gate = 0.18;
    bool echoE = false; double echoS = 0.6; int echoT = 600; double micGain = 1.0;
    ctrl.listen((msg) {
      if (msg is List) {
        final cmd = msg[0];
        if (cmd == 'init') {
          final Map m = msg[1] as Map;
          final SendPort ack = msg[2] as SendPort;
          sr = (m['sr'] as int?) ?? sr;
          final lchz = (m['lchz'] as int?) ?? 0;
          final hchz = (m['hchz'] as int?) ?? 0;
          gate = ((m['gate'] as num?)?.toDouble() ?? gate).clamp(0.0, 1.0);
          echoE = (m['echoE'] as bool?) ?? false;
          echoS = ((m['echoS'] as num?)?.toDouble() ?? 0.6).clamp(0.0, 1.0);
          echoT = (m['echoT'] as int?) ?? 600;
          micGain = ((m['mg'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 2.0);
          fHP = (lchz > 0) ? _Biquad.highPass(sr.toDouble(), lchz.toDouble()) : null;
          fLP = (hchz > 0) ? _Biquad.lowPass(sr.toDouble(), hchz.toDouble()) : null;
          ack.send(true);
        } else if (cmd == 'cfg') {
          final Map m = msg[1] as Map;
          sr = (m['sr'] as int?) ?? sr;
          final lchz = (m['lchz'] as int?) ?? 0;
          final hchz = (m['hchz'] as int?) ?? 0;
          gate = ((m['gate'] as num?)?.toDouble() ?? gate).clamp(0.0, 1.0);
          echoE = (m['echoE'] as bool?) ?? echoE;
          echoS = ((m['echoS'] as num?)?.toDouble() ?? echoS).clamp(0.0, 1.0);
          echoT = (m['echoT'] as int?) ?? echoT;
          micGain = ((m['mg'] as num?)?.toDouble() ?? micGain).clamp(0.0, 2.0);
          fHP = (lchz > 0) ? _Biquad.highPass(sr.toDouble(), lchz.toDouble()) : null;
          fLP = (hchz > 0) ? _Biquad.lowPass(sr.toDouble(), hchz.toDouble()) : null;
        } else if (cmd == 'proc') {
          final int id = msg[1] as int;
          final Uint8List chunk = msg[2] as Uint8List;
          final double rxEma = (msg[3] as num).toDouble();
          final SendPort reply = msg[4] as SendPort;
          // gate by RMS
          if (!_passesGate(chunk, gate)) { reply.send([id, false, Uint8List(0)]); return; }
          // echo suppression (simple)
          Uint8List pcm = chunk;
          if (echoE && rxEma > echoT) {
            final double factor = (1.0 - echoS).clamp(0.0, 1.0);
            if (factor < 1.0) pcm = _gainPcm16(Uint8List.fromList(pcm), factor);
          }
          // mic gain
          if (micGain != 1.0) pcm = _gainPcm16(Uint8List.fromList(pcm), micGain);
          // EQ
          if (fHP != null || fLP != null) {
            pcm = _eqPcm16(Uint8List.fromList(pcm), fHP, fLP);
          }
          reply.send([id, true, pcm]);
        }
      }
    });
  }
}

bool _passesGate(Uint8List pcm, double gate) {
  try {
    if (pcm.lengthInBytes < 2) return false;
    final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
    double acc = 0.0;
    int count = 0;
    for (int i = 0; i < pcm.lengthInBytes; i += 2) {
      final s = bd.getInt16(i, Endian.little).toDouble();
      acc += s * s; count++;
    }
    if (count == 0) return false;
    final rms = sqrt(acc / count) / 32768.0;
    return rms > gate;
  } catch (_) { return true; }
}

Uint8List _gainPcm16(Uint8List pcm, double gain) {
  try {
    final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
    for (int i = 0; i < pcm.lengthInBytes; i += 2) {
      int s = bd.getInt16(i, Endian.little);
      double v = s * gain;
      if (v > 32767) v = 32767; if (v < -32768) v = -32768;
      bd.setInt16(i, v.toInt(), Endian.little);
    }
    return pcm;
  } catch (_) { return pcm; }
}

Uint8List _eqPcm16(Uint8List pcm, _Biquad? hp, _Biquad? lp) {
  try {
    final bd = ByteData.view(pcm.buffer, 0, pcm.lengthInBytes);
    for (int i = 0; i < pcm.lengthInBytes; i += 2) {
      int s = bd.getInt16(i, Endian.little);
      double v = s.toDouble();
      if (hp != null) v = hp.process(v);
      if (lp != null) v = lp.process(v);
      if (v > 32767) v = 32767; if (v < -32768) v = -32768;
      bd.setInt16(i, v.toInt(), Endian.little);
    }
    return pcm;
  } catch (_) { return pcm; }
}

class _Biquad {
  final double b0, b1, b2, a1, a2; double _z1 = 0.0; double _z2 = 0.0;
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);
  static _Biquad lowPass(double fs, double fc, {double q = 1.0 / 1.41421356237}) {
    final w0 = 2 * pi * (fc / fs); final cw = cos(w0); final sw = sin(w0); final alpha = sw / (2 * q);
    double b0 = (1 - cw) / 2; double b1 = 1 - cw; double b2 = (1 - cw) / 2; double a0 = 1 + alpha; double a1 = -2 * cw; double a2 = 1 - alpha;
    return _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }
  static _Biquad highPass(double fs, double fc, {double q = 1.0 / 1.41421356237}) {
    final w0 = 2 * pi * (fc / fs); final cw = cos(w0); final sw = sin(w0); final alpha = sw / (2 * q);
    double b0 = (1 + cw) / 2; double b1 = -(1 + cw); double b2 = (1 + cw) / 2; double a0 = 1 + alpha; double a1 = -2 * cw; double a2 = 1 - alpha;
    return _Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }
  double process(double x) { final y = b0 * x + _z1; _z1 = b1 * x - a1 * y + _z2; _z2 = b2 * x - a2 * y; return y; }
}

