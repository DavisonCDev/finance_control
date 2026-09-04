import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import 'accounts_screen.dart';
import 'transactions_screen.dart';
import 'budgets_screen.dart';
import 'reports_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Account> accounts = [];
  List<Transaction> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final [accountsRes, transactionsRes] = await Future.wait([
        ApiService.get('/accounts'),
        ApiService.get('/transactions'),
      ]);

      setState(() {
        accounts = (ApiService.decode(accountsRes) as List).map((e) => Account.fromJson(e)).toList();
        transactions = (ApiService.decode(transactionsRes) as List).map((e) => Transaction.fromJson(e)).toList();
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  double get totalBalance => accounts.fold(0, (sum, a) => sum + a.currentBalance);
  double get monthlyIncome => transactions
      .where((t) => t.isIncome && t.date.month == DateTime.now().month)
      .fold(0, (sum, t) => sum + t.amount);
  double get monthlyExpense => transactions
      .where((t) => t.isExpense && t.date.month == DateTime.now().month)
      .fold(0, (sum, t) => sum + t.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Control'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetsScreen())),
                            icon: const Icon(Icons.flag),
                            label: const Text('Orçamentos'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen())),
                            icon: const Icon(Icons.pie_chart),
                            label: const Text('Relatórios'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildCard('Saldo total', totalBalance, Colors.blue.shade900),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildCard('Receitas', monthlyIncome, Colors.green)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildCard('Despesas', monthlyExpense, Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Contas', () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const AccountsScreen()))
                          .then((_) => _loadData())),
                    const SizedBox(height: 8),
                    accounts.isEmpty
                        ? const Text('Nenhuma conta cadastrada.')
                        : Column(
                            children: accounts
                                .map((a) => ListTile(
                                      leading: CircleAvatar(
                                        child: Text(a.name.substring(0, 1).toUpperCase()),
                                      ),
                                      title: Text(a.name),
                                      subtitle: Text(Account.typeLabel(a.type)),
                                      trailing: Text(
                                        'R\$ ${a.currentBalance.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ))
                                .toList(),
                          ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Últimas transações', () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const TransactionsScreen()))
                          .then((_) => _loadData())),
                    const SizedBox(height: 8),
                    transactions.isEmpty
                        ? const Text('Nenhuma transação.')
                        : Column(
                            children: transactions
                                .take(5)
                                .map((t) => ListTile(
                                      leading: Icon(
                                        t.isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                                        color: t.isIncome ? Colors.green : Colors.red,
                                      ),
                                      title: Text(t.description ?? t.categoryName ?? 'Transação'),
                                      subtitle: Text(t.accountName ?? ''),
                                      trailing: Text(
                                        'R\$ ${t.amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: t.isIncome ? Colors.green : Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCard(String label, double value, Color color) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              'R\$ ${value.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        TextButton(onPressed: onTap, child: const Text('Ver todos')),
      ],
    );
  }
}
