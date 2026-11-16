// AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
// Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import 'dart:typed_data';

// Non-web platforms: no browser speech engine. The UI explains it and keeps the text.
bool ttsSupported() => false;
bool prefersReducedMotion() => false;
Future<bool> speak(List<String> sentences, String lang,
        {required void Function() onDone, required void Function(String) onError}) async =>
    false;
void pause() {}
void resume() {}
void cancel() {}
void unlockAudio() {}
Future<bool> playAudio(Uint8List bytes, {required void Function() onEnded, required void Function(String) onError}) async =>
    false;
void pauseAudio() {}
void resumeAudio() {}
void stopAudio() {}
