import 'dart:ui' show AppExitResponse;

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
  runApp(PdcWalletApp(
    controller: WalletController(engine.core, isDemoEngine: engine.isDemo, pollInterval: const Duration(seconds: 5)),
  ));
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

class PdcWalletApp extends StatefulWidget {
  const PdcWalletApp({super.key, required this.controller});

  final WalletController controller;

  @override
  State<PdcWalletApp> createState() => _PdcWalletAppState();
}

class _PdcWalletAppState extends State<PdcWalletApp> {
  late final AppLifecycleListener _lifecycle;

  WalletController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Stop the wallet engine before the process exits: on Windows an engine still running at exit can leave a process that
    // never ends. Failures must not keep the window from closing.
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) => controller.setForeground(s == AppLifecycleState.resumed || s == AppLifecycleState.inactive),
      onExitRequested: () async {
        try {
          await controller.shutdown().timeout(const Duration(seconds: 10));
        } on Object {
          // exit anyway
        }
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
