import 'package:flutter/material.dart';

import 'services/api_service.dart';

class AiAnalysisPanel extends StatefulWidget {
  const AiAnalysisPanel({
    super.key,
    required this.api,
    required this.latitude,
    required this.longitude,
    required this.configured,
  });

  final ApiService api;
  final double latitude;
  final double longitude;
  final bool? configured;

  @override
  State<AiAnalysisPanel> createState() => _AiAnalysisPanelState();
}

class _AiAnalysisPanelState extends State<AiAnalysisPanel> {
  final _question = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  int _requestId = 0;

  @override
  void didUpdateWidget(covariant AiAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _requestId++;
      _loading = false;
      _error = null;
      _result = null;
    }
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.api.analyzeZone(
        widget.latitude,
        widget.longitude,
        question: _question.text,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _result?['analysis'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text('Explicación con Gemini',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Se enviarán a Gemini las coordenadas seleccionadas, los datos de '
          'demostración y tu pregunta.',
        ),
        if (widget.configured == false)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Gemini aún no está configurado en el servidor.'),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _question,
          maxLength: 1000,
          maxLines: 2,
          enabled: !_loading && widget.configured != false,
          decoration: const InputDecoration(
            labelText: 'Pregunta opcional',
            hintText: '¿Qué significa este desplazamiento?',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          onPressed: _loading || widget.configured == false ? null : _analyze,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_loading ? 'Analizando…' : 'Analizar con Gemini'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (analysis != null) ...[
          const SizedBox(height: 12),
          Text(_result!['notice'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(analysis['summary'] as String),
          _section('Observaciones', analysis['observations'] as List<dynamic>),
          _section('Limitaciones', analysis['limitations'] as List<dynamic>),
          _section('Siguientes pasos',
              analysis['suggested_next_steps'] as List<dynamic>),
          const SizedBox(height: 8),
          const Text(
            'Explicación generada por IA; requiere revisión humana.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _section(String title, List<dynamic> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $item'),
            ),
        ],
      ),
    );
  }
}

