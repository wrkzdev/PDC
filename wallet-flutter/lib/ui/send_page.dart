import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../core/amount.dart';
import '../core/asset_rules.dart';
import '../wallet/wallet_core.dart';
import 'common.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _to = TextEditingController();
  final _amount = TextEditingController();
  final _comment = TextEditingController();
  AssetId _asset = AssetId.native;
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    _comment.dispose();
    super.dispose();
  }

  AssetBalance? _balanceOf(AssetId id) {
    for (final b in widget.controller.balances) {
      if (b.assetId == id) return b;
    }
    return null;
  }

  Future<void> _send() async {
    final c = widget.controller;
    setState(() => _error = null);
    try {
      final b = _balanceOf(_asset);
      if (b == null) throw FormatException('Pick an asset.');
      final to = _to.text.trim();
      if (!to.startsWith('Px')) throw FormatException('PDC addresses start with Px.');
      final amount = Amount.parse(_amount.text, decimals: b.decimalPoint);
      if (amount.isZero) throw FormatException('Enter an amount greater than zero.');
      final need = _asset.isNative ? amount + defaultFee : amount;
      if (need > b.unlocked) {
        throw FormatException(_asset.isNative
            ? 'Not enough PDC: you have ${b.formatUnlocked()} available and the ${defaultFee.format()} PDC network fee comes on top.'
            : 'Not enough ${b.ticker}: you have ${b.formatUnlocked()} available.');
      }
      if (!_asset.isNative && !c.canPayFee) {
        throw FormatException('You need at least ${defaultFee.format()} PDC unlocked to pay the network fee.');
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm payment'),
          content: Text('Send ${amount.format(decimals: b.decimalPoint)} ${b.ticker} to\n$to\n\n'
              'Network fee: ${defaultFee.format()} PDC. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      );
      if (ok != true) return;
      final tx = await c.send(to, amount, _asset, _comment.text);
      if (!mounted) return;
      _amount.clear();
      _comment.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sent. Transaction ${tx.substring(0, 12)}...'),
        action: SnackBarAction(label: 'Copy id', onPressed: () => copyText(context, tx, what: 'Transaction id copied')),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  /// Everything spendable of the selected asset; for PDC the network fee is kept back.
  void _fillMax() {
    final b = _balanceOf(_asset);
    if (b == null) return;
    var max = b.unlocked;
    if (_asset.isNative) max = max > defaultFee ? max - defaultFee : Amount.zero;
    _amount.text = max.format(decimals: b.decimalPoint);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Send', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<AssetId>(
            initialValue: _asset,
            decoration: const InputDecoration(labelText: 'Asset'),
            items: [
              for (final b in c.balances)
                DropdownMenuItem(value: b.assetId, child: Text('${b.ticker}  (${b.formatUnlocked()} available)')),
            ],
            onChanged: (v) => setState(() => _asset = v ?? AssetId.native),
          ),
          const SizedBox(height: 12),
          TextField(controller: _to, decoration: const InputDecoration(labelText: 'Recipient address')),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              suffixIcon: TextButton(onPressed: _fillMax, child: const Text('Max')),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _comment, decoration: const InputDecoration(labelText: 'Comment (optional, stored in your wallet)')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: c.busy ? null : _send, child: const Text('Review and send')),
        ],
      ),
    );
  }
}
