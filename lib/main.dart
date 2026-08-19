import 'package:flutter/material.dart';

void main() {
  runApp(const NovaApp());
}

/// Application shell.
///
/// Deliberately empty until WP-7 builds the Now / Focus / Chat screens and
/// WP-8 wires the composition root. Keeping this minimal means the layer guard
/// and the test suite are meaningful from the first commit.
class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C6EF5)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('Nova')),
      ),
    );
  }
}
