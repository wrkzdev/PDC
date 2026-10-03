import 'package:flutter/material.dart';

import 'app/wallet_controller.dart';
import 'ui/home_page.dart';
import 'ui/welcome_page.dart';
import 'wallet/mock_wallet_core.dart';

void main() {
  // The native engine (wallet2 behind plain_wallet_api, over dart:ffi / WebAssembly) replaces this in the next
  // phase; until then the app runs on the in-memory demo engine and says so on every screen.
  runApp(PdcWalletApp(controller: WalletController(MockWalletCore(), isDemoEngine: true)));
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
