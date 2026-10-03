import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../core/amount.dart';
import '../core/asset_rules.dart';
import '../wallet/wallet_core.dart';
import 'common.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key, required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final assets = c.balances.where((b) => !b.assetId.isNative).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: Text('Assets', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Add an asset by id',
                  onPressed: () => _addById(context),
                  icon: const Icon(Icons.playlist_add),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeployAssetPage(controller: c))),
                  icon: const Icon(Icons.add),
                  label: const Text('Deploy asset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (assets.isEmpty) const Text('You do not hold any assets yet. Deploy one, or receive one from someone.'),
            for (final a in assets)
              Card(
                child: ListTile(
                  title: Text('${a.formatUnlocked()} ${a.ticker}'),
                  subtitle: Text('${a.fullName}\n${a.assetId.hex}'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _manage(context, a, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'emit', child: Text('Emit more (owner only)')),
                      PopupMenuItem(value: 'burn', child: Text('Burn')),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Assets someone sent you stay hidden until you add them by id (the wallet engine's whitelist rule).
  Future<void> _addById(BuildContext context) async {
    final text = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add an asset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Assets other people send you are hidden until you add them. Paste the asset id (64 hex characters). '
                'Only add assets you recognise: anyone can create an asset with any name.'),
            TextField(controller: text, autofocus: true, decoration: const InputDecoration(labelText: 'Asset id')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, text.text.trim().toLowerCase()), child: const Text('Add')),
        ],
      ),
    );
    text.dispose();
    if (id == null || !context.mounted) return;
    try {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) throw FormatException('An asset id is 64 hexadecimal characters.');
      await controller.addCustomAsset(AssetId(id));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset added')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _manage(BuildContext context, AssetBalance a, String action) async {
    final controllerText = TextEditingController();
    final isEmit = action == 'emit';
    final amountText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEmit ? 'Emit ${a.ticker}' : 'Burn ${a.ticker}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isEmit
                ? 'Creates new coins to this wallet. Only the asset owner can do this, up to the maximum supply. Fee: ${defaultFee.format()} PDC.'
                : 'Destroys coins permanently and reduces the supply. This cannot be undone. Fee: ${defaultFee.format()} PDC.'),
            TextField(
              controller: controllerText,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controllerText.text), child: Text(isEmit ? 'Emit' : 'Burn')),
        ],
      ),
    );
    controllerText.dispose();
    if (amountText == null || !context.mounted) return;
    try {
      final amount = Amount.parse(amountText, decimals: a.decimalPoint);
      final tx = isEmit ? await controller.emitAsset(a.assetId, amount) : await controller.burnAsset(a.assetId, amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submitted. Transaction ${tx.substring(0, 12)}...')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }
}

class DeployAssetPage extends StatefulWidget {
  const DeployAssetPage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<DeployAssetPage> createState() => _DeployAssetPageState();
}

class _DeployAssetPageState extends State<DeployAssetPage> {
  final _ticker = TextEditingController();
  final _name = TextEditingController();
  final _meta = TextEditingController();
  final _decimals = TextEditingController(text: '12');
  final _max = TextEditingController();
  final _initial = TextEditingController();
  List<String> _problems = const [];

  @override
  void dispose() {
    for (final c in [_ticker, _name, _meta, _decimals, _max, _initial]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Builds a draft from the form, or fills [_problems] and returns null.
  AssetDraft? _draft() {
    final problems = <String>[];
    final decimals = int.tryParse(_decimals.text.trim());
    if (decimals == null) problems.add('Decimal places must be a whole number.');
    BigInt? max, initial;
    if (decimals != null && decimals >= 0 && decimals <= AssetRules.maxDecimalPoint) {
      try {
        max = AssetRules.parseSupply(_max.text, decimals);
      } on Object {
        problems.add('Maximum supply is not a valid number with up to $decimals decimal places.');
      }
      try {
        initial = AssetRules.parseSupply(_initial.text.isEmpty ? '0' : _initial.text, decimals);
      } on Object {
        problems.add('Initial supply is not a valid number with up to $decimals decimal places.');
      }
    }
    if (problems.isEmpty) {
      final draft = AssetDraft(
        ticker: _ticker.text.trim(),
        fullName: _name.text.trim(),
        metaInfo: _meta.text.trim(),
        decimalPoint: decimals!,
        totalMaxSupply: max!,
        initialSupply: initial!,
      );
      problems.addAll(AssetRules.validate(draft));
      if (problems.isEmpty) {
        setState(() => _problems = const []);
        return draft;
      }
    }
    setState(() => _problems = problems);
    return null;
  }

  Future<void> _deploy() async {
    final c = widget.controller;
    final draft = _draft();
    if (draft == null) return;
    if (!c.canPayFee) {
      setState(() => _problems = ['You need at least ${defaultFee.format()} PDC unlocked to pay the network fee.']);
      return;
    }
    String fmt(BigInt v) => Amount.fromAtomic(v).format(decimals: draft.decimalPoint);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deploy this asset?'),
        content: Text('Ticker: ${draft.ticker}\nName: ${draft.fullName}\nDecimal places: ${draft.decimalPoint}\n'
            'Maximum supply: ${fmt(draft.totalMaxSupply)}\nInitial supply (sent to you): ${fmt(draft.initialSupply)}\n\n'
            'Network fee: ${defaultFee.format()} PDC.\n'
            'The ticker, name, decimals and maximum supply cannot be changed afterwards. '
            'You become the owner and can emit up to the maximum.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deploy')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await c.deployAsset(draft);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Asset submitted'),
          content: SelectableText('Asset id:\n${r.assetId.hex}\n\nTransaction:\n${r.txId}\n\n'
              'The asset exists once the transaction is confirmed.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _problems = [describeError(e)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Deploy asset')),
      body: SafeArea(
        child: Column(
          children: [
            DemoBanner(controller: c),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _ticker,
                    decoration: const InputDecoration(labelText: 'Ticker', helperText: '1-14 letters or digits, e.g. GOLD'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 12),
                  TextField(controller: _meta, decoration: const InputDecoration(labelText: 'Description (optional)')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _decimals,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Decimal places', helperText: '0-18 (PDC itself uses 12)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Maximum supply', helperText: 'Fixed forever once deployed'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _initial,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Initial supply', helperText: 'Created now and sent to your address; you can emit the rest later'),
                  ),
                  for (final p in _problems)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(p, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: c,
                    builder: (_, _) => FilledButton(
                      onPressed: c.busy ? null : _deploy,
                      child: Text('Deploy (fee ${defaultFee.format()} PDC)'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
