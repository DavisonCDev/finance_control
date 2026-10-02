import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../utils/icon_map.dart';
import 'card_detail_screen.dart';
import 'new_transaction_screen.dart';
import '../utils/formatters.dart';

// Item da lista: uma transacao real ou uma fatura de cartao (no vencimento).
class _Entry {
  _Entry.tx(this.tx) : invoice = null, date = tx!.date;
  _Entry.inv(this.invoice)
      : tx = null,
        date = DateTime.parse('${invoice['due_date']}'.substring(0, 10));
  final DateTime date;
  final Transaction? tx;
  final dynamic invoice;

  // Fatura conta como "paga" quando esta quitada.
  bool get paid => tx?.isPaid ?? invoice['status'] == 'paid';
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

// Estado dos filtros: intervalo de datas + tipo + situacao + conta +
// categoria + busca por texto.
class _Filter {
  DateTime? from;
  DateTime? to;
  String type = 'all'; // all | expense | income | transfer
  bool? paid;          // null = todas as situacoes
  int? accountId;
  int? categoryId;
  String query = '';
  String periodLabel = 'Todos';

  bool get isActive =>
      from != null ||
      to != null ||
      type != 'all' ||
      paid != null ||
      accountId != null ||
      categoryId != null ||
      query.isNotEmpty;

  _Filter copy() => _Filter()
    ..from = from
    ..to = to
    ..type = type
    ..paid = paid
    ..accountId = accountId
    ..categoryId = categoryId
    ..query = query
    ..periodLabel = periodLabel;

  void copyFrom(_Filter o) {
    from = o.from;
    to = o.to;
    type = o.type;
    paid = o.paid;
    accountId = o.accountId;
    categoryId = o.categoryId;
    query = o.query;
    periodLabel = o.periodLabel;
  }

  void clear() {
    from = null;
    to = null;
    type = 'all';
    paid = null;
    accountId = null;
    categoryId = null;
    query = '';
    periodLabel = 'Todos';
  }
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> transactions = [];
  List<dynamic> invoices = [];
  List<Account> accounts = [];
  List<Category> categories = [];
  bool loading = true;
  final _filter = _Filter();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [tRes, iRes, aRes, cRes] = await Future.wait([
      ApiService.get('/transactions?limit=1000&order=date_desc'),
      ApiService.get('/cards/invoices'),
      ApiService.get('/accounts'),
      ApiService.get('/categories?flat=true'),
    ]);
    setState(() {
      final data = ApiService.decode(tRes) as Map<String, dynamic>;
      transactions = (data['transactions'] as List? ?? [])
          .map((e) => Transaction.fromJson(e))
          .toList();
      invoices = ApiService.decode(iRes) is List
          ? ApiService.decode(iRes) as List
          : [];
      accounts = ApiService.decode(aRes) is List
          ? (ApiService.decode(aRes) as List)
              .map((e) => Account.fromJson(e))
              .toList()
          : [];
      categories = ApiService.decode(cRes) is List
          ? (ApiService.decode(cRes) as List)
              .map((e) => Category.fromJson(e))
              .toList()
          : [];
      loading = false;
    });
  }

  Future<void> _openAdd() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.arrow_downward, color: Colors.red.shade600),
              title: const Text('Despesa'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            ListTile(
              leading: Icon(Icons.arrow_upward, color: Colors.green.shade600),
              title: const Text('Receita'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.orange),
              title: const Text('Transferência'),
              onTap: () => Navigator.pop(context, 'transfer'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final changed = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewTransactionScreen(initialType: type)),
    );
    if (changed == true) _load();
  }

  Future<void> _openEdit(Transaction t) async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewTransactionScreen(transactionToEdit: t)),
    );
    if (changed == true) _load();
  }

  // Venceu: data anterior a hoje e ainda nao paga.
  bool _isOverdue(DateTime d) {
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  // Lista de transacoes sem as compras no cartao: elas aparecem na tela
  // do cartao. O pagamento da fatura (invoice_payment) tambem fica oculto
  // porque a fatura ja e exibida como item na data de vencimento.
  List<_Entry> get _allEntries {
    final list = <_Entry>[
      for (final t in transactions)
        if (t.cardId == null && t.source != 'invoice_payment') _Entry.tx(t),
      for (final i in invoices)
        if (((i['total_amount'] as num?)?.toDouble() ?? 0) > 0) _Entry.inv(i),
    ];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // Ids aceitos pelo filtro de categoria: a escolhida + suas
  // subcategorias (mesmo comportamento do backend).
  Set<int>? get _categoryScope {
    final id = _filter.categoryId;
    if (id == null) return null;
    return {
      id,
      for (final c in categories)
        if (c.parentId == id) c.id,
    };
  }

  bool _matches(_Entry e) {
    final f = _filter;
    if (f.from != null &&
        e.date.isBefore(DateTime(f.from!.year, f.from!.month, f.from!.day))) {
      return false;
    }
    if (f.to != null &&
        e.date.isAfter(
            DateTime(f.to!.year, f.to!.month, f.to!.day, 23, 59, 59))) {
      return false;
    }
    // Fatura entra como "despesa"; paga quando a fatura esta quitada.
    final type = e.tx?.type ?? 'expense';
    if (f.type != 'all' && type != f.type) return false;
    final paid = e.tx?.isPaid ?? e.invoice['status'] == 'paid';
    if (f.paid != null && paid != f.paid) return false;

    // Filtros que so fazem sentido em transacoes: fatura de cartao nao
    // tem categoria nem conta, entao sai da lista quando eles estao ativos.
    if (f.accountId != null) {
      final t = e.tx;
      if (t == null ||
          (t.accountId != f.accountId &&
              t.transferAccountId != f.accountId)) {
        return false;
      }
    }
    final catScope = _categoryScope;
    if (catScope != null && !catScope.contains(e.tx?.categoryId)) {
      return false;
    }
    if (f.query.isNotEmpty) {
      final q = f.query.toLowerCase();
      final haystack = e.tx != null
          ? '${e.tx!.description ?? ''} ${e.tx!.categoryLabel ?? ''} '
              '${e.tx!.accountName ?? ''}'
          : 'fatura ${e.invoice['card_name'] ?? ''}';
      if (!haystack.toLowerCase().contains(q)) return false;
    }
    return true;
  }

  List<_Entry> get _entries =>
      _allEntries.where(_matches).toList();

  // Aba "Pagas": so lancamentos baixados, mais recentes primeiro.
  List<_Entry> get _past => _entries.where((e) => e.paid).toList();

  // Aba "Futuras": tudo que nao foi pago, mesmo vencido — atrasadas
  // aparecem primeiro (data mais antiga no topo).
  List<_Entry> get _future {
    final list = _entries.where((e) => !e.paid).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  // Aplica um preset de periodo no filtro [f]; devolve o rotulo do
  // periodo ou null se o usuario cancelou um picker.
  Future<String?> _applyPeriod(_Filter f, String key) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'all':
        f.from = null;
        f.to = null;
        return 'Todos';
      case 'today':
        f.from = today;
        f.to = today;
        return 'Hoje';
      case 'yesterday':
        f.from = today.subtract(const Duration(days: 1));
        f.to = f.from;
        return 'Ontem';
      case 'week':
        f.from = today.subtract(Duration(days: today.weekday - 1));
        f.to = f.from!.add(const Duration(days: 6));
        return 'Esta semana';
      case 'month':
        f.from = DateTime(today.year, today.month);
        f.to = DateTime(today.year, today.month + 1, 0);
        return 'Este mês';
      case 'last_month':
        f.from = DateTime(today.year, today.month - 1);
        f.to = DateTime(today.year, today.month, 0);
        return 'Mês passado';
      case 'day':
        final d = await showDatePicker(
          context: context,
          initialDate: f.from ?? today,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (d == null) return null;
        f.from = d;
        f.to = d;
        return fmtDate(d);
      case 'range':
        final r = await showDateRangePicker(
          context: context,
          initialDateRange: f.from != null && f.to != null
              ? DateTimeRange(start: f.from!, end: f.to!)
              : null,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (r == null) return null;
        f.from = r.start;
        f.to = r.end;
        return '${fmtDate(r.start)} – ${fmtDate(r.end)}';
    }
    return null;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_Filter>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // Copia editavel: cancelar nao altera os filtros ativos.
        final draft = _filter.copy();
        final queryCtrl = TextEditingController(text: draft.query);
        // Dropdown de categorias: cada pai seguido das suas filhas.
        final sortedCats = [...categories]..sort((a, b) {
            final ga = a.parentId ?? a.id;
            final gb = b.parentId ?? b.id;
            if (ga != gb) return ga.compareTo(gb);
            final childA = a.parentId != null ? 1 : 0;
            final childB = b.parentId != null ? 1 : 0;
            if (childA != childB) return childA - childB;
            return a.name.compareTo(b.name);
          });
        return StatefulBuilder(
          builder: (context, setSheet) {
            Widget section(String title, List<Widget> children) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, children: children),
                    ],
                  ),
                );

            ChoiceChip chip(
              String label,
              bool selected,
              void Function() onPick,
            ) =>
                ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setSheet(onPick),
                );

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16, 16, 16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtrar transações',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      section('Período', [
                        for (final (k, l) in [
                          ('all', 'Todos'),
                          ('today', 'Hoje'),
                          ('yesterday', 'Ontem'),
                          ('week', 'Esta semana'),
                          ('month', 'Este mês'),
                          ('last_month', 'Mês passado'),
                          ('day', 'Dia…'),
                          ('range', 'Intervalo…'),
                        ])
                          chip(l, draft.periodLabel == l, () async {
                            final label = await _applyPeriod(draft, k);
                            if (label != null) draft.periodLabel = label;
                          }),
                      ]),
                      section('Tipo', [
                        chip('Todas', draft.type == 'all',
                            () => draft.type = 'all'),
                        chip('Despesas', draft.type == 'expense',
                            () => draft.type = 'expense'),
                        chip('Receitas', draft.type == 'income',
                            () => draft.type = 'income'),
                        chip('Transferências', draft.type == 'transfer',
                            () => draft.type = 'transfer'),
                      ]),
                      section('Situação', [
                        chip('Todas', draft.paid == null,
                            () => draft.paid = null),
                        chip('Pagas', draft.paid == true,
                            () => draft.paid = true),
                        chip('A pagar', draft.paid == false,
                            () => draft.paid = false),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: queryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Buscar',
                          hintText: 'Descrição, categoria ou conta',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => draft.query = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: draft.accountId ?? -1,
                        decoration: const InputDecoration(
                          labelText: 'Conta',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('Todas as contas'),
                          ),
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                        ],
                        onChanged: (v) => setSheet(
                          () => draft.accountId = v == -1 ? null : v,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: draft.categoryId ?? -1,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('Todas as categorias'),
                          ),
                          for (final c in sortedCats)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.parentId != null ? '— ${c.name}' : c.name,
                              ),
                            ),
                        ],
                        onChanged: (v) => setSheet(
                          () => draft.categoryId = v == -1 ? null : v,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setSheet(() {
                              draft.clear();
                              queryCtrl.clear();
                            }),
                            child: const Text('Limpar'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, draft),
                            child: const Text('Aplicar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() => _filter.copyFrom(result));
  }

  // Resumo dos filtros ativos exibido acima das listas.
  Widget _filterBanner() {
    final accountName = accounts
        .where((a) => a.id == _filter.accountId)
        .map((a) => a.name)
        .firstOrNull;
    final categoryName = categories
        .where((c) => c.id == _filter.categoryId)
        .map((c) => c.name)
        .firstOrNull;
    final parts = <String>[
      if (_filter.from != null) _filter.periodLabel,
      switch (_filter.type) {
        'expense' => 'Despesas',
        'income' => 'Receitas',
        'transfer' => 'Transferências',
        _ => '',
      },
      if (_filter.paid == true) 'Pagas',
      if (_filter.paid == false) 'A pagar',
      ?accountName,
      ?categoryName,
      if (_filter.query.isNotEmpty) '"${_filter.query}"',
    ].where((s) => s.isNotEmpty).join(' • ');
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Filtro: $parts',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () => setState(_filter.clear),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Agrupa por data na ordem em que a lista vier.
  List<Widget> _buildGrouped(List<_Entry> list) {
    final items = <Widget>[];
    String? lastKey;
    for (final e in list) {
      final key =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      if (key != lastKey) {
        lastKey = key;
        items.add(_dayHeader(e.date));
      }
      items.add(e.tx != null ? _tile(e.tx!) : _invoiceTile(e.invoice));
    }
    return items;
  }

  Widget _dayHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    String label = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    if (day == today) {
      label = 'Hoje • $label';
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = 'Ontem • $label';
    } else if (day == today.add(const Duration(days: 1))) {
      label = 'Amanhã • $label';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Color _hex(String? hex, Color fallback) {
    if (hex == null) return fallback;
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Widget _tile(Transaction t) {
    // Transferencia e compra no cartao mantem icone proprio; os demais
    // usam o icone e a cor da categoria.
    final (icon, color) = t.isTransfer
        ? (Icons.swap_horiz, Colors.orange.shade700)
        : t.cardId != null
            ? (Icons.credit_card, Colors.deepPurple)
            : (
                iconFromName(t.categoryIcon),
                _hex(
                  t.categoryColor,
                  t.isIncome ? Colors.green.shade600 : Colors.red.shade600,
                ),
              );

    final subtitle = t.isTransfer
        ? '${t.accountName ?? ''} → ${t.transferAccountName ?? ''}'
        : [
            if (t.categoryLabel != null) t.categoryLabel,
            if (t.cardName != null) t.cardName else t.accountName,
          ].whereType<String>().join(' • ');

    // Nao paga e vencida => "Atrasada" em vermelho; senao "A pagar".
    final status = t.isPaid
        ? null
        : _isOverdue(t.date) ? 'Atrasada' : 'A pagar';

    return ListTile(
      onTap: () => _openEdit(t),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(t.description ?? t.categoryLabel ?? 'Transação'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: subtitle),
            if (status != null)
              TextSpan(
                text: '${subtitle.isEmpty ? '' : ' • '}$status',
                style: status == 'Atrasada'
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      )
                    : null,
              ),
          ],
        ),
      ),
      trailing: Text(
        '${t.isIncome ? '+' : t.isExpense ? '-' : ''}R\$ ${fmtMoney(t.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Fatura de cartao exibida na data de vencimento; abre o detalhe do cartao.
  Widget _invoiceTile(dynamic inv) {
    final paid = inv['status'] == 'paid';
    final amount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final remaining = (inv['remaining'] as num?)?.toDouble() ?? amount;
    final due = DateTime.parse('${inv['due_date']}'.substring(0, 10));
    final overdue = !paid && _isOverdue(due);
    final dueStr = '${due.day.toString().padLeft(2, '0')}/'
        '${due.month.toString().padLeft(2, '0')}/${due.year}';
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardDetailScreen(
            cardId: inv['card_id'],
            cardName: '${inv['card_name'] ?? 'Cartão'}',
          ),
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
        child: const Icon(Icons.credit_card, color: Colors.deepPurple),
      ),
      title: Text('Fatura ${inv['card_name'] ?? ''}'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: paid
                  ? 'Paga'
                  : remaining < amount
                      ? 'Parcial — restam R\$ ${fmtMoney(remaining)}'
                      : 'Vence $dueStr',
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
        '-R\$ ${fmtMoney(amount)}',
        style: const TextStyle(
          color: Colors.deepPurple,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tab(List<_Entry> list, String empty) {
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(child: Text(empty)),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: _buildGrouped(list),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transações'),
          actions: [
            IconButton(
              tooltip: 'Filtros',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _filter.isActive,
                smallSize: 8,
                child: const Icon(Icons.filter_list),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pagas'),
              Tab(text: 'Futuras'),
            ],
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_filter.isActive) _filterBanner(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _tab(_past, 'Nenhuma transação paga.'),
                        _tab(_future, 'Nenhuma pendência.'),
                      ],
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'transactions_fab',
          onPressed: _openAdd,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
