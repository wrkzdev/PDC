import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../core/secret_keys.dart';
import '../core/seed_phrase.dart';
import '../wallet/wallet_core.dart';
import 'common.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _Mode { create, restore, open }

/// What a restore starts from.
enum _RestoreFrom { phrase, keys }

class _WelcomePageState extends State<WelcomePage> {
  late _Mode _mode = widget.controller.lastWalletName == null
      ? _Mode.create
      : _Mode.open;
  late final _name = TextEditingController(
    text: widget.controller.lastWalletName ?? 'my-wallet',
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _seed = TextEditingController();
  final _seedPassword = TextEditingController();
  final _spendKey = TextEditingController();
  final _viewKey = TextEditingController();
  _RestoreFrom _restoreFrom = _RestoreFrom.phrase;
  late final _node = TextEditingController(text: widget.controller.node.url);
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _password, _confirm, _seed, _seedPassword, _spendKey, _viewKey, _node]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "26 words" under the phrase field, so a missing or extra word is visible while typing.
  String _wordCountLabel() {
    final n = seedWordCount(normalizeSeedPhrase(_seed.text));
    return n == 0 ? '' : '$n words';
  }

  Future<void> _submit() async {
    final c = widget.controller;
    setState(() => _error = null);
    try {
      final endpoint = NodeEndpoint(_node.text.trim());
      if (_name.text.trim().isEmpty) {
        throw FormatException('Give the wallet a name.');
      }
      if (_password.text.length < 8 && _mode != _Mode.open) {
        throw FormatException('Use a password of at least 8 characters.');
      }
      c.node = endpoint;
      switch (_mode) {
        case _Mode.create:
          if (_password.text != _confirm.text) {
            throw FormatException('The passwords do not match.');
          }
          final seed = await c.createWallet(_name.text.trim(), _password.text);
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _SeedDialog(seed: seed),
          );
        case _Mode.restore:
          if (_restoreFrom == _RestoreFrom.keys) {
            final spend = normalizeSecretKey(_spendKey.text, 'spend key');
            final view = normalizeSecretKey(_viewKey.text, 'view key');
            try {
              await c.restoreWalletFromKeys(_name.text.trim(), _password.text, spend, view);
            } on WalletException catch (e) {
              // the engine answers WRONG_SEED for any pair it cannot use
              if (e.message.contains('WRONG_SEED')) {
                throw FormatException(
                  'These keys are not valid or do not belong together. Check the spend key and the view key of the same wallet.',
                );
              }
              rethrow;
            }
          } else {
            final phrase = checkSeedPhrase(_seed.text);
            try {
              await c.restoreWallet(
                _name.text.trim(),
                _password.text,
                phrase,
                _seedPassword.text,
              );
            } on WalletException catch (e) {
              // the engine answers WRONG_SEED for a wrong word, a wrong count and a missing or wrong seed password alike
              if (e.message.contains('WRONG_SEED')) {
                throw FormatException(
                  _seedPassword.text.isEmpty
                      ? 'That recovery phrase was not accepted. If it came from the CLI wallet\'s show_seed, it was most likely '
                          'secured with a seed password (show_seed asks for one): enter it in "Seed password" and try again. '
                          'Otherwise check every word and their order.'
                      : 'That recovery phrase was not accepted with this seed password. The seed password is the one typed at '
                          'show_seed ("Enter seed password"), which is not the wallet password unless you used the same one. '
                          'Also check every word and their order.',
                );
              }
              rethrow;
            }
          }
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
                        Text(
                          'PDC Wallet',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connects to a PDC node; keys never leave this device.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<_Mode>(
                          segments: const [
                            ButtonSegment(
                              value: _Mode.create,
                              label: Text('Create'),
                            ),
                            ButtonSegment(
                              value: _Mode.restore,
                              label: Text('Restore'),
                            ),
                            ButtonSegment(
                              value: _Mode.open,
                              label: Text('Open'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _node,
                          decoration: const InputDecoration(
                            labelText: 'Node address',
                            helperText:
                                'https://node.example.org or http://node.example.org:19211',
                          ),
                        ),
                        NodeAdvisory(field: _node, isDemoEngine: c.isDemoEngine),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Wallet name',
                          ),
                        ),
                        if (_mode == _Mode.restore) ...[
                          const SizedBox(height: 12),
                          SegmentedButton<_RestoreFrom>(
                            segments: const [
                              ButtonSegment(
                                value: _RestoreFrom.phrase,
                                label: Text('Recovery phrase'),
                              ),
                              ButtonSegment(
                                value: _RestoreFrom.keys,
                                label: Text('Secret keys'),
                              ),
                            ],
                            selected: {_restoreFrom},
                            onSelectionChanged: (s) => setState(() {
                              _restoreFrom = s.first;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          if (_restoreFrom == _RestoreFrom.phrase) ...[
                            TextField(
                              controller: _seed,
                              minLines: 2,
                              maxLines: 4,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Recovery phrase',
                                helperText: '25 or 26 words',
                                counterText: _wordCountLabel(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _seedPassword,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Seed password (optional)',
                                helperText: 'Only if you protected the phrase with one when you made the wallet',
                              ),
                            ),
                          ] else ...[
                            TextField(
                              controller: _spendKey,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Secret spend key',
                                helperText: '64 hex characters (simplewallet: spendkey)',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _viewKey,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Secret view key',
                                helperText: '64 hex characters (simplewallet: viewkey)',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A wallet restored from keys works like any other, but it has no recovery phrase: keep these keys safe.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                        if (_mode == _Mode.create) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirm,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Repeat password',
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ListenableBuilder(
                          listenable: c,
                          builder: (_, _) => FilledButton(
                            onPressed: c.busy ? null : _submit,
                            child: c.busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(switch (_mode) {
                                    _Mode.create => 'Create wallet',
                                    _Mode.restore => 'Restore wallet',
                                    _Mode.open => 'Open wallet',
                                  }),
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
          const Text(
            'These words are the only way to recover your funds. Anyone who has them can spend your coins. '
            'Store them offline; never share or photograph them.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            widget.seed,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
          ),
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
        FilledButton(
          onPressed: _saved ? () => Navigator.of(context).pop() : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
