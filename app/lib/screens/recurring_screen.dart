import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<dynamic> items = [];
  List<Account> accounts = [];
  List<Category> categories = [];
  List<dynamic> cards = [];
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

  Future<void> _delete(dynamic r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar recorrência?'),
        content: Text(
          'A recorrência "${r['description'] ?? ''}" e as transações geradas por ela serão removidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.delete('/recurring/${r['id']}');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Recorrência removida')));
        }
      }
    }
  }

  Future<void> _showConfirmDialog(dynamic r) async {
    // Recorrencia em conta pode ter so ESTA ocorrencia paga no cartao:
    // o lancamento vira compra na fatura e nao sai do saldo em conta.
    final onAccount = r['card_id'] == null;
    if (onAccount && cards.isEmpty) await _loadMetadata();
    if (!mounted) return;
    final canUseCard =
        onAccount && r['type'] == 'expense' && cards.isNotEmpty;
    int? cardId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Confirmar débito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r['card_id'] != null
                    ? 'Lançar "${r['description'] ?? ''}" de R\$ ${fmtMoney((r['amount'] as num))} na fatura do cartão?'
                    : 'A recorrência "${r['description'] ?? ''}" de R\$ ${fmtMoney((r['amount'] as num))} prevista para ${fmtDate(r['next_date'])} foi realizada?',
              ),
              if (canUseCard) ...[
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Conta'),
                      icon: Icon(Icons.account_balance, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Cartão'),
                      icon: Icon(Icons.credit_card, size: 16),
                    ),
                  ],
                  selected: {cardId != null},
                  onSelectionChanged: (s) => setDialog(() {
                    cardId = s.first ? (cardId ?? cards.first['id'] as int) : null;
                  }),
                ),
                if (cardId != null) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: cardId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Cartão'),
                    items: [
                      for (final c in cards)
                        DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text('${c['name']}'),
                        ),
                    ],
                    onChanged: (v) => setDialog(() => cardId = v),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(cardId != null ? 'Lançar na fatura' : 'Sim, debitar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.post('/recurring/${r['id']}/generate', {
        'card_id': ?cardId,
      });
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                cardId != null
                    ? 'Compra lançada na fatura'
                    : 'Débito confirmado',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _openCreate({dynamic r}) async {
    final isEditing = r != null;
    await _loadMetadata();
    if (!mounted) return;

    final descriptionController = TextEditingController(
      text: isEditing ? (r['description'] ?? '') : '',
    );
    final amountController = TextEditingController(
      text: isEditing ? fmtMoney((r['amount'] as num)) : '',
    );
    final endDateController = TextEditingController(
      text: isEditing && r['end_date'] != null ? fmtDate(r['end_date']) : '',
    );
    String type = isEditing ? r['type'] : 'expense';
    int? accountId = isEditing ? r['account_id'] : null;
    int? cardId = isEditing ? r['card_id'] : null;
    int? categoryId = isEditing ? r['category_id'] : null;
    String frequency = isEditing ? r['frequency'] : 'monthly';
    DateTime startDate = isEditing
        ? DateTime.tryParse(r['start_date'] ?? '') ?? DateTime.now()
        : DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableCategories = categories
              .where((c) => c.type == type)
              .toList();

          Future<void> pickStartDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: startDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2050),
            );
            if (picked != null) {
              setDialogState(() => startDate = picked);
            }
          }

          return AlertDialog(
            title: Text(isEditing ? 'Editar recorrência' : 'Nova recorrência'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('Despesa')),
                      ButtonSegment(value: 'income', label: Text('Receita')),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) {
                      setDialogState(() {
                        type = v.first;
                        categoryId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Despesa pode ser recorrente em conta ou no cartao —
                  // no cartao cada mes vira compra dentro da fatura.
                  if (type == 'expense' && cards.isNotEmpty)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Conta'),
                          icon: Icon(Icons.account_balance, size: 16),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Cartão'),
                          icon: Icon(Icons.credit_card, size: 16),
                        ),
                      ],
                      selected: {cardId != null},
                      onSelectionChanged: (s) => setDialogState(() {
                        if (s.first) {
                          cardId ??= cards.first['id'] as int;
                          accountId = null;
                        } else {
                          cardId = null;
                        }
                      }),
                    ),
                  const SizedBox(height: 12),
                  if (cardId != null)
                    DropdownButtonFormField<int>(
                      initialValue: cardId,
                      decoration:
                          const InputDecoration(labelText: 'Cartão'),
                      items: [
                        for (final c in cards)
                          DropdownMenuItem(
                            value: c['id'] as int,
                            child: Text('${c['name']}'),
                          ),
                      ],
                      onChanged: (v) => setDialogState(() => cardId = v),
                    )
                  else if (accounts.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: accountId,
                      decoration: const InputDecoration(labelText: 'Conta'),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => accountId = v),
                    ),
                  const SizedBox(height: 12),
                  if (availableCategories.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      items: availableCategories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => categoryId = v),
                    ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data do primeiro débito'),
                    subtitle: Text(
                      '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: pickStartDate,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frequência'),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Diária')),
                      DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                      DropdownMenuItem(value: 'monthly', child: Text('Mensal')),
                      DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                    ],
                    onChanged: (v) => setDialogState(() => frequency = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endDateController,
                    decoration: const InputDecoration(
                      labelText: 'Data final (opcional)',
                      hintText: 'DD/MM/AAAA',
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
                  if (descriptionController.text.isEmpty ||
                      amountController.text.isEmpty ||
                      (accountId == null && cardId == null) ||
                      categoryId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Preencha todos os campos obrigatórios'),
                      ),
                    );
                    return;
                  }
                  final amount = parseMoney(amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Informe um valor válido')),
                    );
                    return;
                  }
                  var end = endDateController.text.trim();
                  final brDate = RegExp(
                    r'^(\d{2})/(\d{2})/(\d{4})$',
                  ).firstMatch(end);
                  if (brDate != null) {
                    end =
                        '${brDate.group(3)}-${brDate.group(2)}-${brDate.group(1)}';
                  }
                  final formattedStart =
                      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
                  final body = {
                    'account_id': cardId == null ? accountId : null,
                    'card_id': cardId,
                    'category_id': categoryId,
                    'type': type,
                    'amount': amount,
                    'description': descriptionController.text,
                    'frequency': frequency,
                    'start_date': formattedStart,
                    'end_date': end.isEmpty ? null : end,
                  };
                  final http.Response res;
                  if (isEditing) {
                    res = await ApiService.put('/recurring/${r['id']}', body);
                  } else {
                    res = await ApiService.post('/recurring', body);
                  }
                  if (res.statusCode == 200 || res.statusCode == 201) {
                    if (context.mounted) Navigator.pop(context);
                    _load();
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao salvar: ${res.statusCode}'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadMetadata() async {
    final [aRes, cRes, cardRes] = await Future.wait([
      ApiService.get('/accounts'),
      ApiService.get('/categories'),
      ApiService.get('/cards'),
    ]);
    setState(() {
      accounts = (ApiService.decode(aRes) as List)
          .map((e) => Account.fromJson(e))
          .toList();
      categories = (ApiService.decode(cRes) as List)
          .map((e) => Category.fromJson(e))
          .toList();
      cards = ApiService.decode(cardRes) is List
          ? ApiService.decode(cardRes) as List
          : [];
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

  Widget _itemTile(dynamic r) {
    final isDue =
        DateTime.tryParse(
          r['next_date'] ?? '',
        )?.isBefore(DateTime.now().add(const Duration(days: 1))) ??
        false;
    final investment = r['investment_name'];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 26),
      title: Text(r['description'] ?? 'Recorrente'),
      subtitle: Text(
        'R\$ ${fmtMoney((r['amount'] as num))} • Próxima: ${fmtDate(r['next_date'])}\n'
        '${r['card_name'] ?? r['account_name'] ?? ''}'
        '${investment != null ? ' → $investment' : ''}'
        '${r['category_name'] != null ? ' • ${r['category_name']}' : ''}',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _openCreate(r: r),
          ),
          FilledButton(
            onPressed: () => _showConfirmDialog(r),
            child: isDue ? const Text('Confirmar') : const Text('Gerar'),
          ),
          IconButton(
            icon: Icon(
              Icons.delete,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _delete(r),
          ),
        ],
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
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: MediaQuery.sizeOf(context).width >= 1000
          ? FloatingActionButton.extended(
              heroTag: 'recurring_fab',
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nova recorrência'),
            )
          : FloatingActionButton(
              heroTag: 'recurring_fab',
              onPressed: _openCreate,
              child: const Icon(Icons.add),
            ),
    );
  }
}
