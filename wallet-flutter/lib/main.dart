import 'package:flutter/material.dart';

import 'app/wallet_controller.dart';
import 'ui/home_page.dart';
import 'ui/welcome_page.dart';
import 'wallet/engine_choice.dart';
import 'wallet/engine_factory.dart';

void main() {
  final EngineChoice engine;
  try {
    engine = createEngine(requestedEngine);
  } catch (e) {
    // Never fall back to the demo engine silently when something else was asked for.
    runApp(StartupErrorApp(message: e.toString()));
    return;
  }
  runApp(PdcWalletApp(controller: WalletController(engine.core, isDemoEngine: engine.isDemo)));
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('PDC Wallet could not start.\n\n$message'),
          ),
        ),
      ),
    );
  }
}

class PdcWalletApp extends StatelessWidget {
  const PdcWalletApp({super.key, required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3B2F8F);
    return MaterialApp(
      title: 'PDC Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.isOpen ? HomePage(controller: controller) : WelcomePage(controller: controller),
      ),
    );
  }
}
