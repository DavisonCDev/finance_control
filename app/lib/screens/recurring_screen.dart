import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';

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

  // Equivalente mensal da recorrencia, para somar o "custo por mes"
  // de itens com frequencias diferentes.
  static double _monthlyOf(dynamic r) {
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    switch (r['frequency']) {
      case 'daily':
        return amount * 30.44;
      case 'weekly':
        return amount * 4.345;
      case 'biweekly':
        return amount * 2.17;
      case 'bimonthly':
        return amount / 2;
      case 'quarterly':
        return amount / 3;
      case 'semiannual':
        return amount / 6;
      case 'yearly':
        return amount / 12;
      default:
        return amount; // monthly
    }
  }

  List<dynamic> _ofType(String type) =>
      items.where((r) => r['type'] == type).toList();

  double _monthlyTotal(String type) =>
      _ofType(type).fold<double>(0.0, (s, r) => s + _monthlyOf(r));

  // Agrupa pela forma de pagamento: cartao tal, conta tal. Aporte
  // programado continua agrupado na conta de origem — o destino
  // aparece no subtitulo do item.
  Map<String, List<dynamic>> _groupsOf(String type) {
    final map = <String, List<dynamic>>{};
    for (final r in _ofType(type)) {
      final key = r['card_id'] != null
          ? 'card:${r['card_id']}'
          : 'account:${r['account_id'] ?? 'x'}';
      map.putIfAbsent(key, () => []).add(r);
    }
    final entries = map.entries.toList();
    entries.sort(
      (a, b) => b.value
          .fold<double>(0.0, (s, r) => s + _monthlyOf(r))
          .compareTo(a.value.fold<double>(0.0, (s, r) => s + _monthlyOf(r))),
    );
    return {for (final e in entries) e.key: e.value};
  }

  String _groupLabel(List<dynamic> group) {
    final r = group.first;
    return r['card_id'] != null
        ? 'Cartão ${r['card_name'] ?? ''}'
        : 'Conta ${r['account_name'] ?? ''}';
  }

  Widget _summaryCard() {
    final expenses = _monthlyTotal('expense');
    final incomes = _monthlyTotal('income');
    final net = incomes - expenses;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo mensal',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Equivalente por mês das ${items.length} recorrências ativas',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _summaryValue(
                    'Despesas',
                    expenses,
                    Theme.of(context).colorScheme.error,
                  ),
                ),
                Expanded(
                  child: _summaryValue(
                    'Receitas',
                    incomes,
                    Colors.green.shade700,
                  ),
                ),
                Expanded(
                  child: _summaryValue(
                    'Líquido',
                    net,
                    net >= 0
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryValue(String label, double value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            'R\$ ${fmtMoney(value)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      );

  List<Widget> _typeSection(String type, String title, Color color) {
    final groups = _groupsOf(type);
    if (groups.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(
        '$title — R\$ ${fmtMoney(_monthlyTotal(type))}/mês',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold, color: color),
      ),
      const SizedBox(height: 4),
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(
            children: [
              Icon(
                entry.key.startsWith('card:')
                    ? Icons.credit_card
                    : Icons.account_balance,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _groupLabel(entry.value),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'R\$ ${fmtMoney(entry.value.fold<double>(0.0, (s, r) => s + _monthlyOf(r)))}/mês',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        for (final r in entry.value) _itemTile(r),
      ],
    ];
  }

  // Item somente leitura: recorrencias nao se editam nem se apagam
  // aqui — para encerrar uma, exclui-se a transacao gerada por ela
  // (opcao "Todas da série" na exclusao).
  Widget _itemTile(dynamic r) {
    final investment = r['investment_name'];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 26),
      title: Text(r['description'] ?? 'Recorrente'),
      subtitle: Text(
        'Próxima: ${fmtDate(r['next_date'])}\n'
        '${r['card_name'] ?? r['account_name'] ?? ''}'
        '${investment != null ? ' → $investment' : ''}'
        '${r['category_name'] != null ? ' • ${r['category_name']}' : ''}',
      ),
      isThreeLine: true,
      trailing: Text(
        'R\$ ${fmtMoney((r['amount'] as num))}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações recorrentes'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _summaryCard(),
                    ..._typeSection('expense', 'Despesas', error),
                    ..._typeSection(
                      'income',
                      'Receitas',
                      Colors.green.shade700,
                    ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma recorrência ativa.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Para encerrar uma recorrência, exclua uma transação '
                          'gerada por ela e escolha "Todas da série".',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
