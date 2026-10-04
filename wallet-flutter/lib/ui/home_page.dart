import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/wallet_controller.dart';
import '../wallet/engine_errors.dart';
import '../wallet/wallet_core.dart';
import 'assets_page.dart';
import 'common.dart';
import 'send_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = <Widget>[
      _WalletTab(controller: c),
      SendPage(controller: c),
      AssetsPage(controller: c),
      SettingsPage(controller: c),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DemoBanner(controller: c),
            Expanded(child: pages[_tab]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.send_outlined), label: 'Send'),
          NavigationDestination(icon: Icon(Icons.token_outlined), label: 'Assets'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _WalletTab extends StatelessWidget {
  const _WalletTab({required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!c.isSynced) ...[
                LinearProgressIndicator(value: c.syncProgress == 0 ? null : c.syncProgress),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.isSynced ? 'Synchronized' : 'Syncing ${formatSyncPercent(c.syncProgress)}% - balances may be incomplete',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: c.busy ? null : c.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (c.refreshError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Could not update: ${friendlyEngineError(c.refreshError!)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Text('Balances', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final b in c.balances) _BalanceTile(balance: b),
              const SizedBox(height: 16),
              Text('Receive', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: SelectableText(c.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy address',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: c.address));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (c.history.isEmpty) const Text('No transactions yet.'),
              for (final t in c.history) _TxTile(tx: t, balances: c.balances),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance});
  final AssetBalance balance;

  @override
  Widget build(BuildContext context) {
    final locked = balance.total > balance.unlocked;
    return Card(
      child: ListTile(
        title: Text('${balance.formatUnlocked()} ${balance.ticker}', style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text([
          if (balance.fullName.isNotEmpty && balance.fullName != balance.ticker) balance.fullName,
          if (locked) 'total ${balance.formatTotal()} (some is locked)',
        ].join(' - ')),
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.balances});
  final WalletTx tx;
  final List<AssetBalance> balances;

  @override
  Widget build(BuildContext context) {
    AssetBalance? asset;
    for (final b in balances) {
      if (b.assetId == tx.assetId) asset = b;
    }
    final decimals = asset?.decimalPoint ?? 12;
    final ticker = asset?.ticker ?? 'asset ${tx.assetId.hex.substring(0, 8)}';
    return ListTile(
      dense: true,
      leading: Icon(tx.isIncoming ? Icons.call_received : Icons.call_made),
      title: Text('${tx.isIncoming ? '+' : '-'}${tx.amount.format(decimals: decimals)} $ticker'),
      subtitle: Text('${tx.height == 0 ? 'unconfirmed' : 'block ${tx.height}'}${tx.comment.isEmpty ? '' : ' - ${tx.comment}'}'),
    );
  }
}
