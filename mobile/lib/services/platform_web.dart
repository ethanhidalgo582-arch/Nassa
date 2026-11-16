// Web implementation: browser SpeechSynthesis + reduced-motion media query.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool ttsSupported() => globalContext.has('speechSynthesis') && globalContext.has('SpeechSynthesisUtterance');

bool prefersReducedMotion() {
  try {
    return web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch (_) {
    return false;
  }
}

Future<List<web.SpeechSynthesisVoice>> _voices() async {
  final synth = web.window.speechSynthesis;
  var list = synth.getVoices().toDart;
  if (list.isNotEmpty) return list;
  // Chrome loads voices asynchronously.
  final c = Completer<void>();
  synth.onvoiceschanged = ((web.Event _) {
    if (!c.isCompleted) c.complete();
  }).toJS;
  await c.future.timeout(const Duration(milliseconds: 1500), onTimeout: () {});
  return synth.getVoices().toDart;
}

/// Picks a voice for [lang] ('es' / 'en'). Null if the device has none.
Future<web.SpeechSynthesisVoice?> _voiceFor(String lang) async {
  final voices = await _voices();
  final matching = voices.where((v) => v.lang.toLowerCase().startsWith(lang)).toList();
  if (matching.isEmpty) return null;
  const preferred = {'es': ['es-es', 'es-mx', 'es-us', 'es-419'], 'en': ['en-us', 'en-gb']};
  for (final p in preferred[lang] ?? const <String>[]) {
    for (final v in matching) {
      if (v.lang.toLowerCase() == p && v.localService) return v;
    }
  }
  return matching.firstWhere((v) => v.localService, orElse: () => matching.first);
}

int _session = 0;

/// Speaks sentences one after another. Returns false when no voice exists for [lang].
Future<bool> speak(List<String> sentences, String lang, {required void Function() onDone,
    required void Function(String) onError}) async {
  cancel();
  final session = ++_session;
  final voice = await _voiceFor(lang);
  if (voice == null) return false;
  final synth = web.window.speechSynthesis;
  var i = 0;
  void next() {
    if (session != _session) return;
    if (i >= sentences.length) {
      onDone();
      return;
    }
    final u = web.SpeechSynthesisUtterance(sentences[i++])
      ..lang = voice.lang
      ..voice = voice
      ..rate = 0.95
      ..pitch = 1.0;
    u.onend = ((web.Event _) => next()).toJS;
    u.onerror = ((web.SpeechSynthesisErrorEvent e) {
      if (session != _session) return;
      if (e.error == 'interrupted' || e.error == 'canceled') return;
      onError(e.error);
    }).toJS;
    synth.speak(u);
  }

  next();
  return true;
}

void pause() => web.window.speechSynthesis.pause();
void resume() => web.window.speechSynthesis.resume();
void cancel() {
  _session++;
  if (ttsSupported()) web.window.speechSynthesis.cancel();
}

// ---------------------------------------------------------------- audio ---
// Plays Gemini-generated WAV audio through a single <audio> element.
web.HTMLAudioElement? _audio;
String? _objectUrl;
int _audioSession = 0;
const _silentWav = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

/// Must be called synchronously inside the click handler: browsers (Safari, Chrome)
/// only allow sound that starts from a user gesture. Later play() calls reuse it.
void unlockAudio() {
  final a = _audio ??= web.HTMLAudioElement();
  if (a.src.isEmpty || a.src == _silentWav) {
    a.src = _silentWav;
    a.play().toDart.then((_) {}, onError: (_) {});
  }
}

Future<bool> playAudio(Uint8List bytes, {required void Function() onEnded, required void Function(String) onError}) async {
  stopAudio();
  final session = ++_audioSession;
  final a = _audio ??= web.HTMLAudioElement();
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav'));
  _objectUrl = web.URL.createObjectURL(blob);
  a.src = _objectUrl!;
  a.onended = ((web.Event _) {
    if (session == _audioSession) onEnded();
  }).toJS;
  a.onerror = ((web.Event _) {
    if (session == _audioSession) onError('audio');
  }).toJS;
  try {
    await a.play().toDart;
    return true;
  } catch (_) {
    return false;
  }
}

void pauseAudio() => _audio?.pause();
void resumeAudio() => _audio?.play().toDart.then((_) {}, onError: (_) {});
void stopAudio() {
  _audioSession++;
  final a = _audio;
  if (a != null) {
    a.pause();
    a.currentTime = 0;
  }
  if (_objectUrl != null) {
    web.URL.revokeObjectURL(_objectUrl!);
    _objectUrl = null;
  }
}
