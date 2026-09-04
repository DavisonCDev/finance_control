import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/api_service.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> accounts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/accounts');
    setState(() {
      accounts = (ApiService.decode(res) as List).map((e) => Account.fromJson(e)).toList();
      loading = false;
    });
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    String type = 'checking';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova conta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(
              controller: balanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Saldo inicial'),
            ),
            DropdownButtonFormField(
              value: type,
              items: const [
                DropdownMenuItem(value: 'checking', child: Text('Conta corrente')),
                DropdownMenuItem(value: 'savings', child: Text('Poupança')),
                DropdownMenuItem(value: 'cash', child: Text('Dinheiro')),
                DropdownMenuItem(value: 'investment', child: Text('Investimento')),
                DropdownMenuItem(value: 'other', child: Text('Outro')),
              ],
              onChanged: (v) => type = v!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await ApiService.post('/accounts', {
                'name': nameController.text,
                'type': type,
                'initial_balance': double.tryParse(balanceController.text) ?? 0,
              });
              if (mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (_, i) {
                final a = accounts[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
                  title: Text(a.name),
                  subtitle: Text(Account.typeLabel(a.type)),
                  trailing: Text(
                    'R\$ ${a.currentBalance.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'accounts_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
