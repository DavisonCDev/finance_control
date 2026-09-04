import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import 'new_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/transactions');
    setState(() {
      transactions = (ApiService.decode(res) as List).map((e) => Transaction.fromJson(e)).toList();
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transações')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: transactions.length,
              itemBuilder: (_, i) {
                final t = transactions[i];
                return ListTile(
                  leading: Icon(
                    t.isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                    color: t.isIncome ? Colors.green : Colors.red,
                  ),
                  title: Text(t.description ?? t.categoryName ?? 'Transação'),
                  subtitle: Text('${t.accountName ?? ''} • ${t.date.day}/${t.date.month}/${t.date.year}'),
                  trailing: Text(
                    'R\$ ${t.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: t.isIncome ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'transactions_fab',
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewTransactionScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
