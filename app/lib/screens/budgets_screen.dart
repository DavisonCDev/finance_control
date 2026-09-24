import 'package:flutter/material.dart';
import '../utils/icon_map.dart';
import 'package:intl/intl.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Budget> budgets = [];
  List<dynamic> cardInvoices = [];
  List<Category> expenseCategories = [];
  bool loading = true;
  String month = DateTime.now().toIso8601String().substring(0, 7);
  Map<String, dynamic> totals = {};

  final List<String> _months = List.generate(12, (i) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month + (i - 6), 1);
    return d.toIso8601String().substring(0, 7);
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [bRes, cRes] = await Future.wait([
      ApiService.get('/budgets?month=$month'),
      ApiService.get('/categories?type=expense&flat=true'),
    ]);
    setState(() {
      final bData = ApiService.decode(bRes) as Map<String, dynamic>;
      budgets = (bData['budgets'] as List? ?? [])
          .map((e) => Budget.fromJson(e))
          .toList();
      cardInvoices = bData['card_invoices'] as List? ?? [];
      totals = bData['totals'] as Map<String, dynamic>? ?? {};
      expenseCategories = (ApiService.decode(cRes) as List)
          .map((e) => Category.fromJson(e))
          .toList();
      _catById = {for (final c in expenseCategories) c.id: c};
      expenseCategories.sort(
        (a, b) =>
            _catLabel(a).toLowerCase().compareTo(_catLabel(b).toLowerCase()),
      );
      loading = false;
    });
  }

  Map<int, Category> _catById = {};

  String _catLabel(Category c) {
    final p = c.parentId != null ? _catById[c.parentId] : null;
    return p != null ? '${p.name} › ${c.name}' : c.name;
  }

  // Edita (ou remove) a previsao de uma categoria existente.
  Future<void> _editBudget(Budget b) async {
    final controller = TextEditingController(
      text: fmtMoney(b.amount),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Previsão: ${b.categoryName}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [MoneyInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Valor previsto',
            prefixText: 'R\$ ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(
              'Remover',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == 'delete') {
      await ApiService.delete('/budgets/${b.id}');
    } else {
      final amount = parseMoney(result);
      if (amount == null || amount <= 0) return;
      await ApiService.put('/budgets/${b.id}', {'amount': amount});
    }
    _load();
  }

  // Cria uma previsao manual para uma categoria que ainda nao tem.
  Future<void> _addBudget() async {
    final used = budgets.map((b) => b.categoryId).toSet();
    List<Category> subsOf(Category p) => expenseCategories
        .where((c) => c.parentId == p.id && !used.contains(c.id))
        .toList();
    // Pai aparece se ele mesmo ou alguma sub ainda nao tem previsao.
    final parents = expenseCategories
        .where(
          (c) =>
              c.parentId == null &&
              (!used.contains(c.id) || subsOf(c).isNotEmpty),
        )
        .toList();
    if (parents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todas as categorias já têm previsão neste mês.'),
        ),
      );
      return;
    }
    int? parentId;
    int? subId;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          Widget item(Category c) => Row(
                children: [
                  Icon(iconFromName(c.icon), color: c.getColor(), size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              );
          final subs =
              parentId == null ? <Category>[] : subsOf(_catById[parentId]!);
          final parentUsed = used.contains(parentId);
          return AlertDialog(
            title: const Text('Nova previsão'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: parentId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Categoria'),
                  items: parents
                      .map((c) => DropdownMenuItem(value: c.id, child: item(c)))
                      .toList(),
                  onChanged: (v) => setDialog(() {
                    parentId = v;
                    subId = null;
                  }),
                ),
                if (subs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: ValueKey('sub_$parentId'),
                    initialValue: subId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Subcategoria',
                      hintText: parentUsed ? null : 'Opcional',
                    ),
                    items: subs
                        .map(
                          (c) =>
                              DropdownMenuItem(value: c.id, child: item(c)),
                        )
                        .toList(),
                    onChanged: (v) => setDialog(() => subId = v),
                  ),
                ],
                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor previsto',
                    prefixText: 'R\$ ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  // Pai ja com previsao exige escolher a subcategoria.
                  if (parentId == null || (parentUsed && subId == null)) {
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final categoryId = subId ?? parentId;
    final amount = parseMoney(controller.text);
    if (amount == null || amount <= 0 || categoryId == null) return;
    await ApiService.post('/budgets', {
      'category_id': categoryId,
      'amount': amount,
      'budget_month': month,
    });
    _load();
  }

  // Faturas agrupadas por cartao.
  Map<String, List<dynamic>> get _invoicesByCard {
    final map = <String, List<dynamic>>{};
    for (final inv in cardInvoices) {
      final name = '${inv['card_name'] ?? 'Cartão'}';
      map.putIfAbsent(name, () => []).add(inv);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final debito = (totals['budgeted'] as num?)?.toDouble() ?? 0;
    final cartao = (totals['card_forecast'] as num?)?.toDouble() ?? 0;
    final previstoTotal = (totals['forecast_total'] as num?)?.toDouble() ?? 0;
    final gastoTotal = (totals['spent_total'] as num?)?.toDouble() ?? 0;
    final remaining = (totals['remaining'] as num?)?.toDouble() ?? 0;
    final percent = (totals['percent'] as num?)?.toDouble() ?? 0;
    final receitaPrevista =
        (totals['income_forecast'] as num?)?.toDouble() ?? 0;
    final sobraPrevista =
        (totals['projected_leftover'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Orçamento')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: month,
                        decoration: const InputDecoration(labelText: 'Mês'),
                        items: _months
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            month = v;
                            loading = true;
                          });
                          _load();
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Previsão do mês',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              _totalLine(
                                'Previsto em débito (contas e recorrentes)',
                                debito,
                                Theme.of(context).colorScheme.primary,
                              ),
                              _totalLine(
                                'Previsto em cartão (faturas do mês)',
                                cartao,
                                Colors.deepPurple,
                              ),
                              _totalLine(
                                'Receita prevista',
                                receitaPrevista,
                                Colors.green.shade700,
                              ),
                              const Divider(),
                              _totalLine(
                                'Previsto total',
                                previstoTotal,
                                Theme.of(context).colorScheme.primary,
                                bold: true,
                              ),
                              _totalLine(
                                'Pago',
                                gastoTotal,
                                Theme.of(context).colorScheme.error,
                              ),
                              _totalLine(
                                'Restante',
                                remaining,
                                Theme.of(context).colorScheme.tertiary,
                              ),
                              _totalLine(
                                'Previsão de sobra (receita − previsto)',
                                sobraPrevista,
                                sobraPrevista >= 0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                                bold: true,
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (percent / 100).clamp(0.0, 1.0),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${percent.toStringAsFixed(1)}% utilizado',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Despesas em conta',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: _addBudget,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Previsão'),
                          ),
                        ],
                      ),
                      if (budgets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Nenhuma previsão ainda — ela é criada '
                            'automaticamente a cada despesa ou recorrência, '
                            'ou manualmente pelo botão acima.',
                          ),
                        ),
                      ...budgets.map(
                        (b) => ListTile(
                          onTap: () => _editBudget(b),
                          leading: CircleAvatar(
                            backgroundColor: b.getColor(),
                            child: Icon(
                              iconFromName(b.categoryIcon),
                              color: Colors.white,
                            ),
                          ),
                          title: Text(b.categoryName),
                          subtitle: Text(
                            'Pago: R\$ ${fmtMoney(b.spent)}',
                          ),
                          trailing: Text(
                            'R\$ ${fmtMoney(b.amount)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (_invoicesByCard.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Cartões de crédito',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        ..._invoicesByCard.entries.map(
                          (entry) => _buildCardSection(entry.key, entry.value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'budgets_fab',
        onPressed: _addBudget,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCardSection(String cardName, List<dynamic> invoices) {
    final cardTotal = invoices.fold<double>(
      0,
      (s, i) => s + ((i['total_amount'] as num?)?.toDouble() ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                cardName,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                'R\$ ${fmtMoney(cardTotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        ...invoices.map((inv) => _buildInvoiceBlock(inv)),
      ],
    );
  }

  // Fatura + categorias das compras que compõem essa fatura.
  Widget _buildInvoiceBlock(dynamic inv) {
    final categories = (inv['categories'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInvoiceTile(inv),
        ...categories.map(
          (c) => Padding(
            padding: const EdgeInsets.only(left: 40),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.label_outline, size: 20),
              title: Text('${c['category_name']}'),
              trailing: Text(
                'R\$ ${fmtMoney(((c['total'] as num?)?.toDouble() ?? 0))}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceTile(dynamic inv) {
    final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final paid = (inv['paid_amount'] as num?)?.toDouble() ?? 0;
    final isPaid = inv['status'] == 'paid';
    String dueLabel = '';
    if (inv['due_date'] != null) {
      try {
        final d = DateTime.parse('${inv['due_date']}'.substring(0, 10));
        dueLabel = ' • vence ${DateFormat('dd/MM').format(d)}';
      } catch (_) {}
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isPaid ? Colors.green : Colors.deepPurple,
        child: Icon(
          isPaid ? Icons.check : Icons.receipt_long,
          color: Colors.white,
        ),
      ),
      title: Text('Fatura'),
      subtitle: Text(
        isPaid
            ? 'Paga$dueLabel'
            : 'Pago: R\$ ${fmtMoney(paid)}$dueLabel',
      ),
      trailing: Text(
        'R\$ ${fmtMoney(total)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _totalLine(
    String label,
    double value,
    Color color, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          Text(
            'R\$ ${fmtMoney(value)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
