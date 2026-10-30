import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'accounts_screen.dart';
import 'transactions_screen.dart';
import 'recurring_screen.dart';
import 'budgets_screen.dart';
import 'cards_screen.dart';
import 'investments_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _NavItem {
  final int index;
  final String label;
  final IconData icon;
  final Widget Function() builder;
  const _NavItem(this.index, this.label, this.icon, this.builder);
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;

  // Telas são reconstruidas ao trocar de aba: initState recarrega os dados,
  // garantindo que a tela vigente sempre mostre os valores atualizados.
  static final List<_NavItem> _items = [
    _NavItem(0, 'Início', Icons.home, () => const HomeScreen()),
    _NavItem(1, 'Contas', Icons.account_balance, () => const AccountsScreen()),
    _NavItem(2, 'Cartões', Icons.credit_card, () => const CardsScreen()),
    _NavItem(3, 'Transações', Icons.swap_horiz, () => const TransactionsScreen()),
    _NavItem(4, 'Recorrentes', Icons.event_repeat, () => const RecurringScreen()),
    _NavItem(5, 'Orçamento', Icons.flag, () => const BudgetsScreen()),
    _NavItem(6, 'Investimentos', Icons.trending_up, () => const InvestmentsScreen()),
  ];

  void _setIndex(int i) => setState(() => index = i);

  Widget _buildBody() => _items[index].builder();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1100) return _buildDesktop();
    if (width >= 600) return _buildTablet();
    return _buildMobile();
  }

  Widget _buildMobile() {
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: _setIndex,
        type: BottomNavigationBarType.fixed,
        items: _items
            .map(
              (i) => BottomNavigationBarItem(icon: Icon(i.icon), label: i.label),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTablet() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: _setIndex,
            labelType: NavigationRailLabelType.all,
            destinations: _items
                .map(
                  (i) => NavigationRailDestination(
                    icon: Icon(i.icon),
                    label: Text(i.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    return Scaffold(
      body: Row(
        children: [
          // NavigationDrawer fixo (M3): destaque de selecao automatico.
          NavigationDrawer(
            selectedIndex: index,
            onDestinationSelected: _setIndex,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Finance Control',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final i in _items)
                NavigationDrawerDestination(
                  icon: Icon(i.icon),
                  label: Text(i.label),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}
