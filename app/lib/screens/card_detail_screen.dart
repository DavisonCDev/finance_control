import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'card_invoices_screen.dart';
import '../utils/formatters.dart';

class CardDetailScreen extends StatefulWidget {
  final int cardId;
  final String cardName;

  const CardDetailScreen({
    super.key,
    required this.cardId,
    required this.cardName,
  });

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  Map<String, dynamic>? card;
  Map<String, dynamic>? currentInvoice;
  List<dynamic> invoices = [];
  bool loading = true;
  String? error;

  static const _months = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  static const _statusLabels = {
    'open': 'Aberta',
    'closed': 'Fechada',
    'partial': 'Parcial',
    'paid': 'Paga',
    'cancelled': 'Cancelada',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _monthLabel(String? ref) {
    if (ref == null || ref.length < 7) return ref ?? '-';
    final m = int.tryParse(ref.substring(5, 7)) ?? 0;
    if (m < 1 || m > 12) return ref;
    return '${_months[m - 1]}/${ref.substring(0, 4)}';
  }

  double _num(dynamic v) => double.tryParse(v.toString()) ?? 0;

  String _money(dynamic v) => 'R\$ ${fmtMoney(_num(v))}';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.get('/cards/${widget.cardId}'),
        ApiService.get('/cards/${widget.cardId}/invoices'),
        ApiService.get('/cards/${widget.cardId}/invoices/current'),
      ]);
      if (!mounted) return;
      setState(() {
        card = ApiService.decode(results[0]) as Map<String, dynamic>;
        invoices = ApiService.decode(results[1]) as List? ?? [];
        currentInvoice =
            ApiService.decode(results[2]) as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Não foi possível carregar os dados do cartão.';
        loading = false;
      });
    }
  }

  int _daysUntil(String? dateStr) {
    if (dateStr == null) return 0;
    final due = DateTime.tryParse(dateStr.substring(0, 10));
    if (due == null) return 0;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  Color _usageColor(double percent) {
    if (percent >= 85) return Theme.of(context).colorScheme.error;
    if (percent >= 60) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  Future<void> _payInvoice() async {
    final inv = currentInvoice;
    if (inv == null || inv['id'] == null) return;
    final accountsRes = await ApiService.get('/accounts');
    final accounts = ApiService.decode(accountsRes) as List? ?? [];
    if (accounts.isEmpty || !mounted) return;
    int? selectedAccountId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Pagar fatura'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total restante: ${_money(inv['remaining'])}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: selectedAccountId,
                hint: const Text('Selecione a conta'),
                decoration: const InputDecoration(
                  labelText: 'Conta para débito',
                ),
                items: accounts
                    .map<DropdownMenuItem<int?>>(
                      (a) => DropdownMenuItem(
                        value: a['id'] as int,
                        child: Text(a['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedAccountId = v),
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
                if (selectedAccountId == null) return;
                Navigator.pop(context, true);
              },
              child: const Text('Pagar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedAccountId == null) return;

    final res = await ApiService.post(
      '/cards/invoices/${inv['id']}/pay',
      {'account_id': selectedAccountId, 'amount': inv['remaining']},
    );
    if (!mounted) return;
    if (res.statusCode == 200 || res.statusCode == 201) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fatura paga.')));
      _load();
    } else {
      final decoded = ApiService.decode(res);
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? res.body)
          : res.body;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cardName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildLimitCard(),
                  const SizedBox(height: 16),
                  _buildCurrentInvoice(),
                  const SizedBox(height: 16),
                  _buildUpcomingInvoices(),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Histórico completo de faturas'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CardInvoicesScreen(
                            cardId: widget.cardId,
                            cardName: widget.cardName,
                          ),
                        ),
                      );
                      _load();
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLimitCard() {
    final limit = _num(card?['limit_amount']);
    final used = _num(card?['used_limit']);
    final available = _num(card?['available_limit']);
    final percent = limit > 0 ? (used / limit) * 100 : 0.0;
    final color = _usageColor(percent);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Limite do cartão',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (card?['brand'] != null)
                  Chip(label: Text(card!['brand'].toString())),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: limit > 0 ? (percent / 100).clamp(0.0, 1.0) : 0,
                minHeight: 12,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${percent.toStringAsFixed(1)}% utilizado',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _limitStat('Limite', _money(limit), null)),
                Expanded(child: _limitStat('Usado', _money(used), color)),
                Expanded(
                  child: _limitStat('Disponível', _money(available), null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fecha dia ${card?['closing_day'] ?? '-'} • Vence dia ${card?['due_day'] ?? '-'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitStat(String label, String value, Color? valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  Widget _buildCurrentInvoice() {
    final inv = currentInvoice;
    if (inv == null) return const SizedBox.shrink();
    final transactions = inv['transactions'] as List? ?? [];
    final remaining = _num(inv['remaining']);
    final status = inv['status']?.toString() ?? 'open';
    final days = _daysUntil(inv['due_date']?.toString());

    final byCategory = <String, double>{};
    for (final t in transactions) {
      final cat = (t['category_name'] ?? 'Outros').toString();
      final amount = _num(t['amount']) * (t['is_refund'] == 1 ? -1 : 1);
      byCategory[cat] = (byCategory[cat] ?? 0) + amount;
    }
    final topCategories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String dueInfo;
    if (status == 'paid') {
      dueInfo = 'Fatura paga';
    } else if (days > 0) {
      dueInfo = 'Vence em $days dia(s) (${fmtDate(inv['due_date'])})';
    } else if (days == 0) {
      dueInfo = 'Vence hoje';
    } else {
      dueInfo = 'Vencida há ${-days} dia(s) (${fmtDate(inv['due_date'])})';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fatura de ${_monthLabel(inv['reference_month']?.toString())}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(
                  label: Text(_statusLabels[status] ?? status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(dueInfo, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _limitStat('Total', _money(inv['total_amount']), null),
                ),
                Expanded(
                  child: _limitStat('Pago', _money(inv['paid_amount']), null),
                ),
                Expanded(
                  child: _limitStat(
                    'Restante',
                    _money(remaining),
                    remaining > 0
                        ? Theme.of(context).colorScheme.error
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
            if (topCategories.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Gastos por categoria',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              ...topCategories.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(e.key)),
                      Text(
                        _money(e.value),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (transactions.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Compras (${transactions.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...transactions.map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    t['is_refund'] == 1 ? Icons.undo : Icons.shopping_bag,
                    size: 20,
                    color: t['is_refund'] == 1
                        ? Colors.green.shade600
                        : Colors.red.shade400,
                  ),
                  title: Text(
                    (t['description'] ?? t['category_name'] ?? 'Compra')
                        .toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      fmtDate(t['date']),
                      if (t['installment_number'] != null)
                        'Parcela ${t['installment_number']}',
                    ].join(' • '),
                  ),
                  trailing: Text(_money(t['amount'])),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhuma compra nesta fatura.'),
              ),
            if (remaining > 0.01) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.payment),
                  label: Text('Pagar fatura (${_money(remaining)})'),
                  onPressed: _payInvoice,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingInvoices() {
    final currentRef = currentInvoice?['reference_month']?.toString() ?? '';
    final upcoming =
        invoices
            .where(
              (i) =>
                  (i['reference_month']?.toString() ?? '')
                          .compareTo(currentRef) >
                      0 &&
                  i['status'] != 'paid' &&
                  _num(i['total_amount']) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (a['reference_month'] ?? '').toString().compareTo(
              (b['reference_month'] ?? '').toString(),
            ),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compromissos futuros',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (upcoming.isEmpty)
              const Text('Nenhuma fatura futura com parcelas ou compras.')
            else ...[
              ...upcoming.map(
                (i) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_note, size: 20),
                  title: Text(_monthLabel(i['reference_month']?.toString())),
                  subtitle: Text('Vence ${fmtDate(i['due_date'])}'),
                  trailing: Text(
                    _money(i['total_amount']),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total comprometido',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _money(
                      upcoming.fold<double>(
                        0,
                        (sum, i) => sum + _num(i['total_amount']),
                      ),
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
