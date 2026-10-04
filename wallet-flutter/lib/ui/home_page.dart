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

/// Screens at or above this width get a side rail instead of the bottom bar.
const double _wideLayoutWidth = 840;

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination(
    'Wallet',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
  ),
  _Destination('Send', Icons.send_outlined, Icons.send),
  _Destination('Assets', Icons.token_outlined, Icons.token),
  _Destination('Settings', Icons.settings_outlined, Icons.settings),
];

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // Kept alive together so a half-filled Send form is still there after a look at the balance.
    final body = IndexedStack(
      index: _tab,
      children: [
        _WalletTab(controller: c),
        SendPage(controller: c),
        AssetsPage(controller: c),
        SettingsPage(controller: c),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= _wideLayoutWidth;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                DemoBanner(controller: c),
                Expanded(
                  child: Row(
                    children: [
                      if (wide) _rail(context, extended: box.maxWidth >= 1100),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _rail(BuildContext context, {required bool extended}) {
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 210,
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: extended
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PdcMark(size: 40),
                  const SizedBox(width: 12),
                  Text(
                    'PDC Wallet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              )
            : const PdcMark(size: 40),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: extended
                ? TextButton.icon(
                    onPressed: widget.controller.lock,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Lock wallet'),
                  )
                : IconButton(
                    tooltip: 'Lock wallet',
                    onPressed: widget.controller.lock,
                    icon: const Icon(Icons.lock_outline),
                  ),
          ),
        ),
      ),
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
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
          child: PageList(
            children: [
              if (!c.isSynced) ...[
                LinearProgressIndicator(
                  value: c.syncProgress == 0 ? null : c.syncProgress,
                ),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.isSynced
                          ? 'Synchronized'
                          : 'Syncing ${formatSyncPercent(c.syncProgress)}% - balances may be incomplete',
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
                  child: Text(
                    'Could not update: ${friendlyEngineError(c.refreshError!)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Text('Balances', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final b in c.balances) _BalanceTile(balance: b),
              const SizedBox(height: 16),
              Text('Receive', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: SelectableText(
                    c.address,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy address',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: c.address));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address copied')),
                        );
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
        title: Text(
          '${balance.formatUnlocked()} ${balance.ticker}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        subtitle: Text(
          [
            if (balance.fullName.isNotEmpty &&
                balance.fullName != balance.ticker)
              balance.fullName,
            if (locked) 'total ${balance.formatTotal()} (some is locked)',
          ].join(' - '),
        ),
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
      title: Text(
        '${tx.isIncoming ? '+' : '-'}${tx.amount.format(decimals: decimals)} $ticker',
      ),
      subtitle: Text(
        '${tx.height == 0 ? 'unconfirmed' : 'block ${tx.height}'}${tx.comment.isEmpty ? '' : ' - ${tx.comment}'}',
      ),
    );
  }
}
