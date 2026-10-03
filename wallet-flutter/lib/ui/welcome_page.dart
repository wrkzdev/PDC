import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../wallet/wallet_core.dart';
import 'common.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _Mode { create, restore, open }

class _WelcomePageState extends State<WelcomePage> {
  _Mode _mode = _Mode.create;
  final _name = TextEditingController(text: 'my-wallet');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _seed = TextEditingController();
  late final _node = TextEditingController(text: widget.controller.node.url);
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _password, _confirm, _seed, _node]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.controller;
    setState(() => _error = null);
    try {
      final endpoint = NodeEndpoint(_node.text.trim());
      if (!endpoint.isSecureEnough) {
        throw FormatException('Use an https:// node (plain http is only allowed for localhost).');
      }
      if (_name.text.trim().isEmpty) throw FormatException('Give the wallet a name.');
      if (_password.text.length < 8 && _mode != _Mode.open) {
        throw FormatException('Use a password of at least 8 characters.');
      }
      c.node = endpoint;
      switch (_mode) {
        case _Mode.create:
          if (_password.text != _confirm.text) throw FormatException('The passwords do not match.');
          final seed = await c.createWallet(_name.text.trim(), _password.text);
          if (!mounted) return;
          await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _SeedDialog(seed: seed));
        case _Mode.restore:
          await c.restoreWallet(_name.text.trim(), _password.text, _seed.text.trim(), '');
        case _Mode.open:
          await c.openWallet(_name.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DemoBanner(controller: c),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('PDC Wallet', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text('Connects to a PDC node; keys never leave this device.',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 20),
                        SegmentedButton<_Mode>(
                          segments: const [
                            ButtonSegment(value: _Mode.create, label: Text('Create')),
                            ButtonSegment(value: _Mode.restore, label: Text('Restore')),
                            ButtonSegment(value: _Mode.open, label: Text('Open')),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: _node, decoration: const InputDecoration(labelText: 'Node address', helperText: 'https://node.example.org or http://127.0.0.1:19211')),
                        const SizedBox(height: 12),
                        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Wallet name')),
                        if (_mode == _Mode.restore) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _seed,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(labelText: 'Recovery phrase'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                        if (_mode == _Mode.create) ...[
                          const SizedBox(height: 12),
                          TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat password')),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        ListenableBuilder(
                          listenable: c,
                          builder: (_, _) => FilledButton(
                            onPressed: c.busy ? null : _submit,
                            child: c.busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(switch (_mode) { _Mode.create => 'Create wallet', _Mode.restore => 'Restore wallet', _Mode.open => 'Open wallet' }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeedDialog extends StatefulWidget {
  const _SeedDialog({required this.seed});
  final String seed;

  @override
  State<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends State<_SeedDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Write down your recovery phrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('These words are the only way to recover your funds. Anyone who has them can spend your coins. '
              'Store them offline; never share or photograph them.'),
          const SizedBox(height: 12),
          SelectableText(widget.seed, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            title: const Text('I have written it down'),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: _saved ? () => Navigator.of(context).pop() : null, child: const Text('Continue')),
      ],
    );
  }
}
