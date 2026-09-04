import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/card.dart' as models;
import '../services/api_service.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  List<models.CardModel> cards = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/cards');
    setState(() {
      cards = (ApiService.decode(res) as List).map((e) => models.CardModel.fromJson(e)).toList();
      loading = false;
    });
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    final brandController = TextEditingController();
    final closingController = TextEditingController();
    final dueController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo cartão'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(controller: brandController, decoration: const InputDecoration(labelText: 'Bandeira')),
              TextField(controller: limitController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Limite')),
              TextField(controller: closingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dia de fechamento')),
              TextField(controller: dueController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dia de vencimento')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await ApiService.post('/cards', {
                'name': nameController.text,
                'brand': brandController.text,
                'limit_amount': double.tryParse(limitController.text) ?? 0,
                'closing_day': int.tryParse(closingController.text),
                'due_day': int.tryParse(dueController.text),
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
      appBar: AppBar(title: const Text('Cartões de crédito')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: cards.length,
              itemBuilder: (_, i) {
                final c = cards[i];
                return ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(c.name),
                  subtitle: Text('Limite: R\$ ${c.limitAmount.toStringAsFixed(2)}'),
                  trailing: c.dueDay != null ? Text('Venc. dia ${c.dueDay}') : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'cards_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
