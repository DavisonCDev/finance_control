import 'package:flutter/material.dart';
import '../utils/icon_map.dart';
import 'package:intl/intl.dart';
import '../models/account.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

// Item da linha do tempo do saldo: um lancamento (pago ou previsto)
// ou o restante de uma fatura ainda nao paga.
class _FlowItem {
  _FlowItem({
    required this.date,
    required this.label,
    required this.effect,
    required this.pending,
    this.subtitle,
    this.time,
  });
  final DateTime date;
  final String label;
  final double effect;
  final bool pending;
  final String? subtitle;
  final String? time;
}

// Grupo de previsoes sob uma categoria-pai: orcamentos feitos em
// subcategorias entram no somatorio da categoria.
class _BudgetGroup {
  _BudgetGroup(this.categoryId, this.items);
  final int categoryId;
  final List<Budget> items;

  double get amount => items.fold(0.0, (s, b) => s + b.amount);
  double get spent => items.fold(0.0, (s, b) => s + b.spent);
}

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Budget> budgets = [];
  List<dynamic> cardInvoices = [];
  List<Transaction> monthTransactions = [];
  List<Account> accounts = [];
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
    final [bRes, cRes, tRes, aRes] = await Future.wait([
      ApiService.get('/budgets?month=$month'),
      ApiService.get('/categories?type=expense&flat=true'),
      ApiService.get('/transactions?month=$month&limit=1000&order=date_asc'),
      ApiService.get('/accounts'),
    ]);
    setState(() {
      final bData = ApiService.decode(bRes) as Map<String, dynamic>;
      budgets = (bData['budgets'] as List? ?? [])
          .map((e) => Budget.fromJson(e))
          .toList();
      cardInvoices = bData['card_invoices'] as List? ?? [];
      final tData = ApiService.decode(tRes) as Map<String, dynamic>;
      monthTransactions = (tData['transactions'] as List? ?? [])
          .map((e) => Transaction.fromJson(e))
          .toList();
      accounts = ApiService.decode(aRes) is List
          ? (ApiService.decode(aRes) as List)
              .map((e) => Account.fromJson(e))
              .toList()
          : [];
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
    final cat = _catById[b.categoryId];
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Previsão: ${cat != null ? _catLabel(cat) : b.categoryName}'),
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

  // Lancamentos do mes que podem ser confirmados aqui: despesas/receitas
  // e transferencias em conta. Compras no cartao nao entram — elas se
  // pagam como fatura; o lancamento interno de pagamento tambem fica fora.
  List<Transaction> get _entries => monthTransactions
      .where((t) => t.cardId == null && t.source != 'invoice_payment')
      .toList();

  // Pendentes primeiro (mais proximas de vencer no topo), depois os
  // confirmados (mais recentes primeiro).
  List<Transaction> get _pending {
    final list = _entries.where((t) => !t.isPaid).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  List<Transaction> get _confirmed {
    final list = _entries.where((t) => t.isPaid).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // Marca/desmarca pago — e aqui que a baixa de um lancamento acontece.
  Future<void> _togglePaid(Transaction t) async {
    await ApiService.put('/transactions/${t.id}', {'is_paid': !t.isPaid});
    _load();
  }

  Widget _payTile(Transaction t, bool paid) {
    final color = t.isIncome
        ? Colors.green.shade700
        : t.isTransfer
            ? Colors.orange.shade700
            : Colors.red.shade600;
    final sign = t.isIncome ? '+' : t.isExpense ? '-' : '';
    // Pendente com data passada => atrasada.
    final now = DateTime.now();
    final overdue = !paid &&
        DateTime(t.date.year, t.date.month, t.date.day)
            .isBefore(DateTime(now.year, now.month, now.day));
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _togglePaid(t),
      leading: IconButton(
        tooltip: paid ? 'Desmarcar pago' : 'Marcar como pago',
        icon: Icon(
          paid ? Icons.check_circle : Icons.radio_button_unchecked,
          color: paid ? Colors.green : Theme.of(context).colorScheme.outline,
        ),
        onPressed: () => _togglePaid(t),
      ),
      title: Text(
        t.description ?? t.categoryLabel ?? 'Transação',
        style: paid
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: [
                fmtDate(t.date),
                if (t.isTransfer)
                  '${t.accountName ?? ''} → ${t.transferAccountName ?? ''}'
                else if (t.categoryLabel != null)
                  t.categoryLabel!,
                if (t.accountName != null && !t.isTransfer) t.accountName,
              ].join(' • '),
            ),
            if (overdue)
              TextSpan(
                text: ' • Atrasada',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
      trailing: Text(
        '$sign R\$ ${fmtMoney(t.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Previsoes agrupadas pela categoria-pai, em ordem alfabetica.
  List<_BudgetGroup> get _budgetGroups {
    final groups = <int, _BudgetGroup>{};
    for (final b in budgets) {
      final cat = _catById[b.categoryId];
      final parentId = cat?.parentId ?? b.categoryId;
      groups.putIfAbsent(parentId, () => _BudgetGroup(parentId, []))
          .items
          .add(b);
    }
    final list = groups.values.toList();
    list.sort(
      (a, b) => _groupLabel(a).toLowerCase().compareTo(
            _groupLabel(b).toLowerCase(),
          ),
    );
    return list;
  }

  String _groupLabel(_BudgetGroup g) =>
      _catById[g.categoryId]?.name ?? g.items.first.categoryName;

  Category? _groupCategory(_BudgetGroup g) => _catById[g.categoryId];

  // Tile de uma previsao: usado sozinho (sem subcategorias) ou como
  // filho dentro de um grupo expandido.
  Widget _budgetTile(Budget b, {bool child = false, String? label}) {
    final cat = _catById[b.categoryId];
    final color = cat?.getColor() ?? b.getColor();
    return ListTile(
      onTap: () => _editBudget(b),
      contentPadding: child ? const EdgeInsets.only(left: 56) : null,
      dense: child,
      leading: child
          ? null
          : CircleAvatar(
              backgroundColor: color,
              child: Icon(
                iconFromName(cat?.icon ?? b.categoryIcon),
                color: Colors.white,
              ),
            ),
      title: Text(label ?? b.categoryName),
      subtitle: Text('Pago: R\$ ${fmtMoney(b.spent)}'),
      trailing: Text(
        'R\$ ${fmtMoney(b.amount)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _budgetGroupTile(_BudgetGroup g) {
    if (g.items.length == 1) return _budgetTile(g.items.first);
    final cat = _groupCategory(g);
    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: cat?.getColor() ?? g.items.first.getColor(),
        child: Icon(
          iconFromName(cat?.icon ?? g.items.first.categoryIcon),
          color: Colors.white,
        ),
      ),
      title: Text(_groupLabel(g)),
      subtitle: Text(
        'Pago: R\$ ${fmtMoney(g.spent)} • Previsto: R\$ ${fmtMoney(g.amount)}',
      ),
      children: [
        for (final b in g.items)
          _budgetTile(
            b,
            child: true,
            label: _catById[b.categoryId]?.name ?? b.categoryName,
          ),
      ],
    );
  }

  // Contas que compoem o "saldo em contas" (mesma regra da home):
  // poupanca, investimento e carteira ficam de fora.
  Set<int> get _balanceAccountIds => {
        for (final a in accounts)
          if (a.type != 'savings' &&
              a.type != 'investment' &&
              a.type != 'cash')
            a.id,
      };

  // Efeito liquido do lancamento no saldo em contas: despesa sai,
  // receita entra; transferencia so conta quando cruza a fronteira
  // (ex.: corrente -> poupanca reduz o saldo em contas).
  double _effectOnBalance(Transaction t) {
    final ids = _balanceAccountIds;
    if (t.isTransfer) {
      final out = ids.contains(t.accountId) ? t.amount : 0.0;
      final inn = ids.contains(t.transferAccountId) ? t.amount : 0.0;
      return inn - out;
    }
    if (!ids.contains(t.accountId)) return 0;
    return t.isIncome ? t.amount : -t.amount;
  }

  // Linha do tempo do mes em ordem cronologica: lancamentos que mexem
  // no saldo + restante de faturas ainda nao quitadas no vencimento.
  List<_FlowItem> get _flowItems {
    double invoiceRemaining(dynamic inv) =>
        (inv['remaining'] as num?)?.toDouble() ??
        ((inv['total_amount'] as num?)?.toDouble() ?? 0) -
            ((inv['paid_amount'] as num?)?.toDouble() ?? 0);
    final items = <_FlowItem>[
      for (final t in monthTransactions)
        if (_effectOnBalance(t) != 0)
          _FlowItem(
            date: t.date,
            label: t.description ?? t.categoryLabel ?? 'Transação',
            effect: _effectOnBalance(t),
            pending: !t.isPaid,
            subtitle: t.isTransfer
                ? '${t.accountName ?? ''} → ${t.transferAccountName ?? ''}'
                : t.categoryLabel ?? t.accountName,
            time: t.time,
          ),
      for (final inv in cardInvoices)
        if (inv['due_date'] != null && invoiceRemaining(inv) > 0)
          _FlowItem(
            date: DateTime.parse('${inv['due_date']}'.substring(0, 10)),
            label: 'Fatura ${inv['card_name'] ?? ''}',
            effect: -invoiceRemaining(inv),
            pending: true,
            subtitle: 'Vencimento da fatura',
          ),
    ];
    // Cronologico por data + horario; itens sem horario (faturas)
    // entram por ultimo no dia.
    items.sort((a, b) {
      final d = a.date.compareTo(b.date);
      if (d != 0) return d;
      return (a.time ?? '23:59').compareTo(b.time ?? '23:59');
    });
    return items;
  }

  // Saldo atual das contas (mesmo conjunto do card da home).
  double get _currentBalance => accounts
      .where((a) => _balanceAccountIds.contains(a.id))
      .fold(0.0, (s, a) => s + a.currentBalance);

  // Saldo no inicio do mes = saldo de hoje menos o que ja foi baixado
  // dentro do mes selecionado.
  double get _openingBalance {
    final paidEffect = monthTransactions
        .where((t) => t.isPaid)
        .fold(0.0, (s, t) => s + _effectOnBalance(t));
    return _currentBalance - paidEffect;
  }

  // Saldo no fim do mes = abertura + todos os lancamentos (pagos e
  // previstos) + faturas ainda nao quitadas.
  double get _projectedEndBalance {
    var value = _openingBalance;
    for (final item in _flowItems) {
      value += item.effect;
    }
    return value;
  }

  // Realizado no mes: tudo que ja entrou (receitas pagas) ou saiu
  // (despesas pagas) do saldo em contas — inclui pagamento de fatura
  // e transferencia para poupanca/investimento/carteira.
  double get _paidIncomeTotal => monthTransactions
      .where((t) => t.isPaid)
      .fold(0.0, (s, t) {
        final e = _effectOnBalance(t);
        return e > 0 ? s + e : s;
      });

  double get _paidExpenseTotal => monthTransactions
      .where((t) => t.isPaid)
      .fold(0.0, (s, t) {
        final e = _effectOnBalance(t);
        return e < 0 ? s - e : s;
      });

  Widget _flowRow(_FlowItem item, double running) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = item.pending
        ? TextStyle(fontStyle: FontStyle.italic, color: scheme.outline)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd/MM').format(item.date),
                  style: labelStyle ??
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                if (item.time != null)
                  Text(
                    item.time!,
                    style: labelStyle ??
                        TextStyle(color: scheme.outline, fontSize: 10),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.subtitle != null)
                  Text(
                    item.subtitle!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.effect >= 0 ? '+' : '−'} R\$ ${fmtMoney(item.effect.abs())}',
                style: TextStyle(
                  color: item.effect >= 0
                      ? Colors.green.shade700
                      : scheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                'saldo R\$ ${fmtMoney(running)}',
                style: TextStyle(
                  fontSize: 11,
                  color: running < 0 ? scheme.error : scheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Evolucao do saldo ao longo do mes: cada lancamento mostra quanto
  // fica o saldo depois dele; pendentes aparecem em italico.
  Widget _buildFlowCard() {
    final items = _flowItems;
    if (items.isEmpty) return const SizedBox.shrink();
    var running = _openingBalance;
    final rows = <Widget>[];
    for (final item in items) {
      running += item.effect;
      rows.add(_flowRow(item, running));
    }
    final projected = running;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evolução do saldo',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Saldo após cada lançamento do mês',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saldo no início do mês'),
                Text(
                  'R\$ ${fmtMoney(_openingBalance)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 16),
            ...rows,
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Saldo projetado no fim do mês',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'R\$ ${fmtMoney(projected)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        projected < 0 ? scheme.error : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Paga (total ou parcial) a fatura — mesmo endpoint usado no
  // detalhe do cartao; baixa na conta escolhida e atualiza tudo.
  Future<void> _payInvoice(dynamic inv) async {
    final remaining = (inv['remaining'] as num?)?.toDouble() ?? 0;
    if (remaining <= 0 || accounts.isEmpty) return;
    int? accountId;
    final amountCtrl =
        TextEditingController(text: fmtMoney(remaining));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Pagar fatura'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Fatura ${inv['card_name'] ?? ''} '
                '(${inv['reference_month'] ?? ''})'
                ' — vence ${fmtDate(inv['due_date'])}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Valor do pagamento',
                  prefixText: 'R\$ ',
                  helperText: 'Deixe o total para quitar a fatura',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta para débito',
                ),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setDialog(() => accountId = v),
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
                if (accountId == null) return;
                Navigator.pop(context, true);
              },
              child: const Text('Pagar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || accountId == null) return;
    final amount = parseMoney(amountCtrl.text);
    if (amount == null || amount <= 0) return;
    await ApiService.post('/cards/invoices/${inv['id']}/pay', {
      'account_id': accountId,
      'amount': amount,
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
    final previstoTotal = (totals['forecast_total'] as num?)?.toDouble() ?? 0;
    final percent = (totals['percent'] as num?)?.toDouble() ?? 0;
    final receitaPrevista =
        (totals['income_forecast'] as num?)?.toDouble() ?? 0;
    // Planejado: abertura + tudo que esta previsto entrar/sair no mes.
    final saldoFinalPrevisto =
        _openingBalance + receitaPrevista - previstoTotal;
    // Quanto a trajetoria real difere do que foi planejado.
    final diferencaPrevisto = _projectedEndBalance - saldoFinalPrevisto;

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
                                'Saldo no início do mês',
                                _openingBalance,
                                _openingBalance < 0
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                              _totalLine(
                                'Previsão de despesas (contas + cartão)',
                                previstoTotal,
                                Theme.of(context).colorScheme.error,
                              ),
                              _totalLine(
                                'Previsão de receitas',
                                receitaPrevista,
                                Colors.green.shade700,
                              ),
                              const Divider(),
                              _totalLine(
                                'Saldo final previsto',
                                saldoFinalPrevisto,
                                saldoFinalPrevisto >= 0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                                bold: true,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Valores reais',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              _totalLine(
                                'Despesas totais',
                                _paidExpenseTotal,
                                Theme.of(context).colorScheme.error,
                              ),
                              _totalLine(
                                'Receitas somadas',
                                _paidIncomeTotal,
                                Colors.green.shade700,
                              ),
                              const Divider(),
                              _totalLine(
                                'Saldo final real',
                                _currentBalance,
                                _currentBalance >= 0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                                bold: true,
                              ),
                              const Divider(),
                              _totalLine(
                                'Saldo projetado no fim do mês',
                                _projectedEndBalance,
                                _projectedEndBalance >= 0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                                bold: true,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Diferença em relação ao previsto',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${diferencaPrevisto >= 0 ? '+' : '−'}R\$ ${fmtMoney(diferencaPrevisto.abs())}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: diferencaPrevisto >= 0
                                            ? Colors.green.shade700
                                            : Theme.of(context)
                                                .colorScheme
                                                .error,
                                      ),
                                    ),
                                  ],
                                ),
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
                      _buildFlowCard(),
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
                      ..._budgetGroups.map(_budgetGroupTile),
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
                      if (_entries.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Lançamentos do mês',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Toque para confirmar ou desfazer o pagamento.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        if (_pending.isNotEmpty) ...[
                          Text(
                            'Pendentes',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          ..._pending.map((t) => _payTile(t, false)),
                        ],
                        if (_confirmed.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Confirmados',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.green.shade700,
                                ),
                          ),
                          ..._confirmed.map((t) => _payTile(t, true)),
                        ],
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

  // Cartao expansivel: cabecalho mostra nome + total das faturas do
  // mes; expandindo aparecem as faturas com as categorias das compras.
  Widget _buildCardSection(String cardName, List<dynamic> invoices) {
    final cardTotal = invoices.fold<double>(
      0,
      (s, i) => s + ((i['total_amount'] as num?)?.toDouble() ?? 0),
    );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: Colors.deepPurple,
        child: Icon(Icons.credit_card, color: Colors.white),
      ),
      title: Text(
        cardName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${invoices.length} fatura${invoices.length == 1 ? '' : 's'} • '
        'R\$ ${fmtMoney(cardTotal)}',
      ),
      childrenPadding: const EdgeInsets.only(left: 8),
      children: [
        for (final inv in invoices) _buildInvoiceBlock(inv),
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
    final remaining = total - paid;
    return ListTile(
      onTap:
          isPaid ? null : () => _payInvoice(inv),
      leading: CircleAvatar(
        backgroundColor: isPaid ? Colors.green : Colors.deepPurple,
        child: Icon(
          isPaid ? Icons.check : Icons.receipt_long,
          color: Colors.white,
        ),
      ),
      title: const Text('Fatura'),
      subtitle: Text(
        isPaid
            ? 'Paga$dueLabel'
            : 'Pago: R\$ ${fmtMoney(paid)}$dueLabel',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'R\$ ${fmtMoney(total)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (remaining > 0.01)
            IconButton(
              tooltip: 'Pagar fatura',
              icon: const Icon(Icons.payments_outlined, size: 20),
              onPressed: () => _payInvoice(inv),
            ),
        ],
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
