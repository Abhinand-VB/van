import 'package:flutter/material.dart';

void main() {
  runApp(const VanApp());
}

/// Application shell.
///
/// Deliberately minimal until WP-7 builds the Now / Focus / Chat screens and
/// WP-8 wires the composition root. Keeping this small means the layer guard
/// and the test suite stay meaningful while the domain core is built out.
class VanApp extends StatelessWidget {
  const VanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D5B)),
        useMaterial3: true,
      ),
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.park_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('Van', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Domain core built and tested.\nScreens arrive in WP-7.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
