import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<dynamic> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/recurring');
    setState(() {
      items = ApiService.decode(res) as List;
      loading = false;
    });
  }

  Future<void> _generate(int id) async {
    await ApiService.post('/recurring/$id/generate', {});
    _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transação gerada')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transações recorrentes')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final r = items[i];
                return ListTile(
                  title: Text(r['description'] ?? 'Recorrente'),
                  subtitle: Text('R\$ ${r['amount']} • Próxima: ${r['next_date']}'),
                  trailing: FilledButton(
                    onPressed: () => _generate(r['id']),
                    child: const Text('Gerar'),
                  ),
                );
              },
            ),
    );
  }
}
