import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'accounts_screen.dart';
import 'transactions_screen.dart';
import 'budgets_screen.dart';
import 'reports_screen.dart';
import 'cards_screen.dart';
import 'goals_screen.dart';
import 'calendar_screen.dart';
import 'recurring_screen.dart';
import 'installments_screen.dart';
import 'notifications_screen.dart';
import 'families_screen.dart';
import 'import_export_screen.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;

  Future<void> _logout() async {
    await ApiService.removeToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.pie_chart),
              title: const Text('Relatórios'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Calendário'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalendarScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: const Text('Cartões de crédito'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CardsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.track_changes),
              title: const Text('Metas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Recorrentes'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecurringScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.splitscreen),
              title: const Text('Parcelas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InstallmentsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notificações'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Família'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamiliesScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text('Importar / Exportar'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportExportScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Control'),
      ),
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          AccountsScreen(),
          TransactionsScreen(),
          BudgetsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => i == 4 ? _openMenu() : setState(() => index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Contas'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Transações'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Orçamento'),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
        ],
      ),
    );
  }
}
