import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../utils/formatters.dart';

class CardInvoicesScreen extends StatefulWidget {
  final int cardId;
  final String cardName;

  const CardInvoicesScreen({
    super.key,
    required this.cardId,
    required this.cardName,
  });

  @override
  State<CardInvoicesScreen> createState() => _CardInvoicesScreenState();
}

class _CardInvoicesScreenState extends State<CardInvoicesScreen> {
  List<dynamic> invoices = [];
  bool loading = true;

  String _statusLabel(String status) {
    const labels = {
      'open': 'Aberta',
      'closed': 'Fechada',
      'partial': 'Parcial',
      'paid': 'Paga',
      'cancelled': 'Cancelada',
    };
    return labels[status] ?? status;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/cards/${widget.cardId}/invoices');
    setState(() {
      invoices = (ApiService.decode(res) as List? ?? []);
      loading = false;
    });
  }

  Future<void> _payInvoice(dynamic invoice) async {
    final accountsRes = await ApiService.get('/accounts');
    final accounts = ApiService.decode(accountsRes) as List;
    int? selectedAccountId;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Pagar fatura'),
          content: SizedBox(
            width: double.maxFinite,
            child: DropdownButtonFormField<int?>(
              initialValue: selectedAccountId,
              hint: const Text('Selecione a conta'),
              decoration: const InputDecoration(labelText: 'Conta para débito'),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedAccountId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione uma conta primeiro.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                final res = await ApiService.post(
                  '/cards/invoices/${invoice['id']}/pay',
                  {
                    'account_id': selectedAccountId,
                    'amount': invoice['remaining'],
                  },
                );
                if (res.statusCode == 200 || res.statusCode == 201) {
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fatura paga.')),
                    );
                  }
                } else {
                  final decoded = ApiService.decode(res);
                  final msg = decoded is Map
                      ? (decoded['message'] ?? res.body)
                      : res.body;
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Erro: $msg')));
                  }
                }
              },
              child: const Text('Pagar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Faturas - ${widget.cardName}'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: invoices.length,
              itemBuilder: (_, i) {
                final inv = invoices[i];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ExpansionTile(
                    title: Text('Fatura ${inv['reference_month']}'),
                    subtitle: Text(
                      'Total: R\$ ${fmtMoney((inv['total_amount'] ?? 0))} | Restante: R\$ ${fmtMoney((inv['remaining'] ?? 0))}',
                    ),
                    trailing: Chip(
                      label: Text(_statusLabel(inv['status'] ?? '')),
                    ),
                    children: [
                      if (inv['transactions'] == null)
                        FutureBuilder<http.Response>(
                          future: ApiService.get(
                            '/cards/${widget.cardId}/invoices/${inv['reference_month']}',
                          ),
                          builder: (_, snap) {
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final data =
                                ApiService.decode(snap.data!)
                                    as Map<String, dynamic>;
                            return _buildInvoiceDetail(data);
                          },
                        )
                      else
                        _buildInvoiceDetail(inv),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInvoiceDetail(Map<String, dynamic> data) {
    final transactions = data['transactions'] as List? ?? [];
    final remaining = data['remaining'] ?? data['total_amount'] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vencimento: ${fmtDate(data['due_date'])}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('Total: R\$ ${fmtMoney((data['total_amount'] ?? 0))}'),
          Text('Pago: R\$ ${fmtMoney((data['paid_amount'] ?? 0))}'),
          Text('Restante: R\$ ${fmtMoney((remaining))}'),
          const SizedBox(height: 8),
          if (transactions.isEmpty)
            const Text('Sem compras nesta fatura.')
          else
            Column(
              children: transactions
                  .map(
                    (t) => ListTile(
                      leading: Icon(
                        Icons.shopping_bag,
                        color: t['is_refund'] == 1
                            ? Colors.green.shade600
                            : Colors.red.shade600,
                      ),
                      title: Text(
                        t['description'] ?? t['category_name'] ?? 'Compra',
                      ),
                      subtitle: Text(fmtDate(t['date'])),
                      trailing: Text(
                        'R\$ ${fmtMoney((t['amount'] ?? 0))}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          if ((remaining as num) > 0.01)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _payInvoice(data),
                child: const Text('Pagar fatura'),
              ),
            ),
        ],
      ),
    );
  }
}
