import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../exercises.dart';
import '../lang.dart';
import '../native.dart';
import '../theme.dart';

/// Guided break: one or more timed steps with an animation, steps text and an optional English voice-over.
class BreakScreen extends StatefulWidget {
  static const routeName = '/break';
  final String type, kind;
  final bool fromReminder;
  const BreakScreen({super.key, required this.type, required this.kind, this.fromReminder = true});

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> {
  late final List<Exercise> _steps = Exercises.routine(widget.type, widget.kind);
  int _i = 0;
  int _left = 0;
  bool _done = false;
  bool _reported = false;
  String _sound = 'voice';
  Timer? _timer;

  int get _total => Exercises.totalSeconds(_steps);
  int get _elapsed => _steps.take(_i).fold(0, (s, e) => s + e.seconds) + (_steps[_i].seconds - _left);

  @override
  void initState() {
    super.initState();
    Native.settings().then((s) {
      _sound = s['sound'] as String? ?? 'voice';
      _startStep(0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    Native.stopVoice();
    // Leaving early: counts as taken if most of it was done, otherwise skipped.
    if (!_reported) Native.breakDone(widget.type, taken: _done || _elapsed >= _total / 2);
    super.dispose();
  }

  void _startStep(int i) {
    if (!mounted) return;
    setState(() {
      _i = i;
      _left = _steps[i].seconds;
    });
    final e = _steps[i];
    // Every exercise has an English voice-over (res/raw/voice_<slug>.ogg, made by tools/make_voice.py).
    if (_sound == 'voice' && !L.tl) Native.playVoice(e.slug);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    if (_left > 1) {
      setState(() => _left--);
      return;
    }
    _timer?.cancel();
    if (_sound != 'silent') HapticFeedback.heavyImpact();
    if (_i + 1 < _steps.length) {
      _startStep(_i + 1);
    } else {
      Native.stopVoice();
      setState(() {
        _left = 0;
        _done = true;
      });
      _report(true);
    }
  }

  void _report(bool taken) {
    if (_reported) return;
    _reported = true;
    Native.breakDone(widget.type, taken: taken);
  }

  void _skip() {
    _report(false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _done ? _finished() : _step()),
    );
  }

  Widget _step() {
    final e = _steps[_i];
    final progress = _total == 0 ? 0.0 : _elapsed / _total;
    return Column(children: [
      LinearProgressIndicator(value: progress, minHeight: 4, color: C.accent, backgroundColor: C.panel),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        child: Row(children: [
          Text(
            _steps.length > 1 ? L.t('Step ${_i + 1} of ${_steps.length}', 'Hakbang ${_i + 1} sa ${_steps.length}') : L.t('Eye break', 'Break ng mata'),
            style: const TextStyle(color: C.dim),
          ),
          const Spacer(),
          TextButton(onPressed: _skip, child: Text(L.t('Skip', 'Laktawan'))),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
          const SizedBox(height: 8),
          // Portrait 3:4 clips (tools/make_videos.py), capped so the steps below stay on screen.
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: e.hasMedia
                      ? Image.asset(e.asset, fit: BoxFit.cover, gaplessPlayback: true,
                          errorBuilder: (_, _, _) => _placeholder(e))
                      : _placeholder(e),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(e.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          Text(e.steps, style: const TextStyle(fontSize: 16, height: 1.45)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: e.seconds == 0 ? 0 : _left / e.seconds,
                strokeWidth: 5,
                color: C.accent,
                backgroundColor: C.panel2,
              ),
              Text('$_left', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.type == 'eye'
                  ? L.t('Look away now. Your phone will buzz when it\'s done.', 'Tumingin palayo ngayon. Magva-vibrate ang phone kapag tapos na.')
                  : L.t('Follow along. Your phone buzzes at each new step.', 'Sumabay lang. Magva-vibrate ang phone sa bawat bagong hakbang.'),
              style: const TextStyle(color: C.dim),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _placeholder(Exercise e) {
    final hands = Exercises.hands.any((h) => h.slug == e.slug);
    return Container(
      color: C.panel,
      child: Icon(hands ? Icons.back_hand_outlined : (e.slug == 'look_up' ? Icons.self_improvement : Icons.accessibility_new),
          size: 120, color: C.accent),
    );
  }

  Widget _finished() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.check_circle_outline, size: 80, color: C.accent),
        const SizedBox(height: 20),
        Text(L.t('Nice, break done!', 'Ayos, tapos na ang break!'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 10),
        Text(
          widget.kind == 'gaming'
              ? L.t('Your eyes and hands are ready for the next match.', 'Handa na ang iyong mata at kamay sa susunod na laban.')
              : L.t('Your eyes thank you. Carry on.', 'Salamat sa iyong mata. Ituloy mo na.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.dim, fontSize: 16),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () {
            if (widget.fromReminder) {
              SystemNavigator.pop(); // back to the app they were using
            } else {
              Navigator.of(context).maybePop();
            }
          },
          child: Text(widget.fromReminder ? L.t('Back to my app', 'Bumalik sa app ko') : L.t('Close', 'Isara')),
        ),
      ]),
    );
  }
}
