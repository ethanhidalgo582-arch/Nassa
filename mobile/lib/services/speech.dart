// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart' as impl;

enum SpeechState { idle, starting, speaking, paused }

enum SpeechEngine { gemini, browser }

/// Single app-wide reader. Starting a new reading always stops the previous one,
/// so two voices never overlap. Audio never starts automatically.
///
/// Primary engine: Gemini TTS (audio generated on the server from the same text shown
/// on screen). Fallback: the browser's speech synthesis, with a visible notice.
class SpeechController extends ChangeNotifier {
  SpeechState state = SpeechState.idle;
  SpeechEngine? engine;
  String? problem; // 'unsupported' | 'novoice' | 'gemini_fallback' | 'audio_blocked' | error code
  ApiException? geminiError;
  String? owner;
  int _token = 0;

  bool get browserSupported => impl.ttsSupported();

  static List<String> sentences(String text) => text
      .split(RegExp(r'(?<=[.!?;:])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// True while the next Gemini part is still being generated between two parts.
  bool waitingNext = false;

  /// Reads with Gemini when [fetchAudio] is given (part by part: the computed summary plays
  /// while the explanation is generated); otherwise, or if it fails, with the browser voice.
  /// Call it directly from the button's onPressed (user gesture).
  Future<void> speak(String text, String lang,
      {required String owner, Future<Uint8List?> Function(int part)? fetchAudio}) async {
    stop();
    final token = ++_token;
    this.owner = owner;
    problem = null;
    geminiError = null;
    if (fetchAudio != null) {
      impl.unlockAudio(); // synchronous, inside the gesture
      engine = SpeechEngine.gemini;
      _set(SpeechState.starting);
      try {
        final first = await fetchAudio(0);
        if (token != _token) return;
        if (first != null) {
          await _playParts(first, fetchAudio, token);
          return;
        }
      } on ApiException catch (e) {
        if (token != _token) return;
        geminiError = e;
        problem = 'gemini_fallback';
      } on _Blocked {
        if (token != _token) return;
        problem = 'audio_blocked';
      }
    }
    await _speakBrowser(text, lang, token);
  }

  Future<void> _playParts(Uint8List first, Future<Uint8List?> Function(int part) fetch, int token) async {
    var part = 0;
    Uint8List? current = first;
    while (current != null && token == _token) {
      // Prefetch the next part while this one plays.
      final next = fetch(part + 1).then<Uint8List?>((b) => b, onError: (Object _) => null);
      final done = Completer<void>();
      final ok = await impl.playAudio(current, onEnded: () {
        if (!done.isCompleted) done.complete();
      }, onError: (code) {
        if (token == _token) problem = code;
        if (!done.isCompleted) done.complete();
      });
      if (token != _token) return;
      if (!ok) throw _Blocked();
      waitingNext = false;
      _set(SpeechState.speaking);
      await done.future;
      if (token != _token) return;
      if (state == SpeechState.paused) return;
      waitingNext = true;
      notifyListeners();
      current = await next;
      waitingNext = false;
      part++;
    }
    if (token == _token) _set(SpeechState.idle);
  }

  Future<void> _speakBrowser(String text, String lang, int token) async {
    engine = SpeechEngine.browser;
    if (!browserSupported) {
      problem ??= 'unsupported';
      _set(SpeechState.idle);
      return;
    }
    _set(SpeechState.starting);
    final ok = await impl.speak(sentences(text), lang, onDone: () {
      if (token == _token) _set(SpeechState.idle);
    }, onError: (code) {
      if (token == _token) {
        problem = code;
        _set(SpeechState.idle);
      }
    });
    if (token != _token) return;
    if (!ok) {
      problem = problem == 'gemini_fallback' ? 'gemini_fallback_novoice' : 'novoice';
      _set(SpeechState.idle);
    } else if (state == SpeechState.starting) {
      _set(SpeechState.speaking);
    }
  }

  void pause() {
    if (state != SpeechState.speaking) return;
    engine == SpeechEngine.gemini ? impl.pauseAudio() : impl.pause();
    _set(SpeechState.paused);
  }

  void resume() {
    if (state != SpeechState.paused) return;
    engine == SpeechEngine.gemini ? impl.resumeAudio() : impl.resume();
    _set(SpeechState.speaking);
  }

  void stop() {
    _token++;
    impl.stopAudio();
    impl.cancel();
    if (state != SpeechState.idle) _set(SpeechState.idle);
  }

  void _set(SpeechState s) {
    state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    impl.stopAudio();
    impl.cancel();
    super.dispose();
  }
}

class _Blocked implements Exception {}

bool platformPrefersReducedMotion() => impl.prefersReducedMotion();
