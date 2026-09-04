import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/goal.dart';
import '../services/api_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Goal> goals = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/goals');
    setState(() {
      goals = (ApiService.decode(res) as List).map((e) => Goal.fromJson(e)).toList();
      loading = false;
    });
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova meta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome da meta')),
            TextField(controller: targetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor alvo', prefixText: 'R\$ ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await ApiService.post('/goals', {
                'name': nameController.text,
                'target_amount': double.tryParse(targetController.text) ?? 0,
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
      appBar: AppBar(title: const Text('Metas financeiras')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: goals.length,
              itemBuilder: (_, i) {
                final g = goals[i];
                return ListTile(
                  leading: const Icon(Icons.flag),
                  title: Text(g.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: g.percent / 100),
                      Text('R\$ ${g.currentAmount.toStringAsFixed(2)} de R\$ ${g.targetAmount.toStringAsFixed(2)}'),
                    ],
                  ),
                  trailing: Text('${g.percent.toStringAsFixed(0)}%'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'goals_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
