import 'package:flutter/material.dart';
import '../models/card.dart' as models;
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import 'card_detail_screen.dart';
import '../utils/formatters.dart';

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
      cards = (ApiService.decode(res) as List)
          .map((e) => models.CardModel.fromJson(e))
          .toList();
      loading = false;
    });
  }

  Future<void> _confirmDelete(models.CardModel card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir cartão?'),
        content: const Text(
          'Cartões com lançamentos não podem ser excluídos. O histórico será mantido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await ApiService.delete('/cards/${card.id}');
    if (res.statusCode == 200) {
      _load();
    } else {
      final decoded = ApiService.decode(res);
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? res.body)
          : res.body;
      if (res.statusCode == 409 && mounted) {
        final deactivate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Não é possível excluir'),
            content: Text(msg.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Desativar'),
              ),
            ],
          ),
        );
        if (deactivate == true) _deactivate(card);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg.toString())));
        }
      }
    }
  }

  Future<void> _deactivate(models.CardModel card) async {
    final res = await ApiService.put('/cards/${card.id}', {'active': false});
    if (res.statusCode == 200) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cartão desativado.')));
      }
    } else {
      final decoded = ApiService.decode(res);
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? res.body)
          : res.body;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    }
  }

  Future<void> _openForm({models.CardModel? card}) async {
    final isEditing = card != null;
    final nameController = TextEditingController(
      text: isEditing ? card.name : '',
    );
    final limitController = TextEditingController(
      text: isEditing ? fmtMoney(card.limitAmount) : '',
    );
    final brandController = TextEditingController(
      text: isEditing ? card.brand : '',
    );
    final closingController = TextEditingController(
      text: isEditing ? (card.closingDay ?? '').toString() : '',
    );
    final dueController = TextEditingController(
      text: isEditing ? (card.dueDay ?? '').toString() : '',
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar cartão' : 'Novo cartão'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: brandController,
                decoration: const InputDecoration(labelText: 'Bandeira'),
              ),
              TextField(
                controller: limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Limite'),
              ),
              TextField(
                controller: closingController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dia de fechamento',
                ),
              ),
              TextField(
                controller: dueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dia de vencimento',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final body = {
                'name': nameController.text,
                'brand': brandController.text,
                'limit_amount': parseMoney(limitController.text) ?? 0,
                'closing_day': int.tryParse(closingController.text),
                'due_day': int.tryParse(dueController.text),
              };
              if (isEditing) {
                await ApiService.put('/cards/${card.id}', body);
              } else {
                await ApiService.post('/cards', body);
              }
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
      appBar: AppBar(
        title: const Text('Cartões de crédito'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: cards.length,
              itemBuilder: (_, i) {
                final c = cards[i];
                final percent = c.limitAmount > 0
                    ? (c.usedLimit / c.limitAmount)
                    : 0.0;
                final barColor = percent >= 0.85
                    ? Theme.of(context).colorScheme.error
                    : percent >= 0.60
                    ? Colors.orange.shade700
                    : Colors.green.shade700;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CardDetailScreen(cardId: c.id, cardName: c.name),
                        ),
                      );
                      _load();
                    },
                    leading: const Icon(Icons.credit_card),
                    title: Text(c.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Usado R\$ ${fmtMoney(c.usedLimit)} de R\$ ${fmtMoney(c.limitAmount)}'
                          '${c.dueDay != null ? ' • Vence dia ${c.dueDay}' : ''}',
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: percent.clamp(0.0, 1.0),
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          color: barColor,
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openForm(card: c),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _confirmDelete(c),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'cards_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
