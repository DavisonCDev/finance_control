import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../services/api_service.dart';

class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({super.key});

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  List<Account> accounts = [];
  List<Category> categories = [];
  String type = 'expense';
  int? selectedAccountId;
  int? selectedCategoryId;
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  DateTime date = DateTime.now();
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [aRes, cRes] = await Future.wait([
      ApiService.get('/accounts'),
      ApiService.get('/categories?type=$type'),
    ]);
    setState(() {
      accounts = (ApiService.decode(aRes) as List).map((e) => Account.fromJson(e)).toList();
      categories = (ApiService.decode(cRes) as List).map((e) => Category.fromJson(e)).toList();
      if (accounts.isNotEmpty) selectedAccountId = accounts.first.id;
      if (categories.isNotEmpty) selectedCategoryId = categories.first.id;
      loading = false;
    });
  }

  Future<void> _save() async {
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cadastre uma conta primeiro')));
      return;
    }
    if (amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o valor')));
      return;
    }
    if (selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma conta')));
      return;
    }
    if (selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma categoria')));
      return;
    }

    setState(() => saving = true);
    final res = await ApiService.post('/transactions', {
      'account_id': selectedAccountId,
      'category_id': selectedCategoryId,
      'type': type,
      'amount': double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0,
      'date': date.toIso8601String().split('T').first,
      'description': descriptionController.text,
    });
    setState(() => saving = false);

    if (res.statusCode == 201) {
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${res.body}')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova transação')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('Despesa')),
                      ButtonSegment(value: 'income', label: Text('Receita')),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) {
                      setState(() {
                        type = s.first;
                        _load();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Data'),
                    subtitle: Text('${date.day}/${date.month}/${date.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _pickDate,
                  ),
                  if (accounts.isEmpty)
                    const Card(
                      color: Colors.orange,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Você ainda não tem contas. Cadastre uma conta em "Contas".', style: TextStyle(color: Colors.white)),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: selectedAccountId,
                      hint: const Text('Selecione uma conta'),
                      decoration: const InputDecoration(labelText: 'Conta'),
                      items: accounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedAccountId = v),
                    ),
                  const SizedBox(height: 8),
                  if (categories.isEmpty)
                    const Card(
                      color: Colors.orange,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Nenhuma categoria encontrada.', style: TextStyle(color: Colors.white)),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: selectedCategoryId,
                      hint: const Text('Selecione uma categoria'),
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      items: categories
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedCategoryId = v),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: saving ? null : _save,
                      child: saving ? const CircularProgressIndicator() : const Text('Salvar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
