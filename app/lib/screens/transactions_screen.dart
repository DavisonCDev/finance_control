import 'package:flutter/material.dart';
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
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Transaction> transactions = [];
  List<dynamic> invoices = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [tRes, iRes] = await Future.wait([
      ApiService.get('/transactions?limit=1000&order=date_desc'),
      ApiService.get('/cards/invoices'),
    ]);
    setState(() {
      final data = ApiService.decode(tRes) as Map<String, dynamic>;
      transactions = (data['transactions'] as List? ?? [])
          .map((e) => Transaction.fromJson(e))
          .toList();
      invoices = ApiService.decode(iRes) is List
          ? ApiService.decode(iRes) as List
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

  DateTime get _endOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  // Lista de transacoes sem as compras no cartao: elas aparecem na tela
  // do cartao. O pagamento da fatura (invoice_payment) tambem fica oculto
  // porque a fatura ja e exibida como item na data de vencimento.
  List<_Entry> get _entries {
    final list = <_Entry>[
      for (final t in transactions)
        if (t.cardId == null && t.source != 'invoice_payment') _Entry.tx(t),
      for (final i in invoices)
        if (((i['total_amount'] as num?)?.toDouble() ?? 0) > 0) _Entry.inv(i),
    ];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // Ate hoje: hoje primeiro, depois as passadas.
  List<_Entry> get _past =>
      _entries.where((e) => !e.date.isAfter(_endOfToday)).toList();

  // Futuras: da mais proxima para a mais distante.
  List<_Entry> get _future {
    final list = _entries.where((e) => e.date.isAfter(_endOfToday)).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
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
            if (!t.isPaid) 'A pagar',
          ].whereType<String>().join(' • ');

    return ListTile(
      onTap: () => _openEdit(t),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(t.description ?? t.categoryLabel ?? 'Transação'),
      subtitle: Text(subtitle),
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
      subtitle: Text(
        paid
            ? 'Paga'
            : remaining < amount
                ? 'Parcial — restam R\$ ${fmtMoney(remaining)}'
                : 'Vence ${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year}',
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Até hoje'),
              Tab(text: 'Futuras'),
            ],
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _tab(_past, 'Nenhuma transação até hoje.'),
                  _tab(_future, 'Nenhuma transação futura.'),
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
