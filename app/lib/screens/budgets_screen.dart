import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../services/api_service.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Budget> budgets = [];
  List<Category> categories = [];
  bool loading = true;
  final month = DateTime.now().toIso8601String().substring(0, 7);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [bRes, cRes] = await Future.wait([
      ApiService.get('/budgets?month=$month'),
      ApiService.get('/categories?type=expense'),
    ]);
    setState(() {
      budgets = (ApiService.decode(bRes) as List).map((e) => Budget.fromJson(e)).toList();
      categories = (ApiService.decode(cRes) as List).map((e) => Category.fromJson(e)).toList();
      loading = false;
    });
  }

  Future<void> _create() async {
    final amountController = TextEditingController();
    int? selectedCategoryId = categories.isNotEmpty ? categories.first.id : null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo orçamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => selectedCategoryId = v,
            ),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor do orçamento', prefixText: 'R\$ '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (selectedCategoryId == null || amountController.text.isEmpty) return;
              await ApiService.post('/budgets', {
                'category_id': selectedCategoryId,
                'budget_month': month,
                'amount': double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0,
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
      appBar: AppBar(title: const Text('Orçamentos')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: budgets.length,
              itemBuilder: (_, i) {
                final b = budgets[i];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: b.getColor(), child: const Icon(Icons.flag, color: Colors.white)),
                  title: Text(b.categoryName),
                  subtitle: Text(month),
                  trailing: Text(
                    'R\$ ${b.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'budgets_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
