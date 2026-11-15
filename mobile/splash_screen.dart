import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.api});
  final ApiService? api;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final ApiService _api;
  String _statusMessage = 'Conectando con el servidor...';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() => _statusMessage = 'Verificando servidor...');
      await _api.getHealth();
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(api: _api),
        ),
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Sin conexión con el servidor. Reintentando...';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _initializeApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8fafb),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.satellite_alt_rounded,
                size: 80,
                color: Color(0xff16834a),
              ),
              const SizedBox(height: 24),
              const Text(
                'NISAR App',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff16834a),
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xff9aa3ad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}