import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  List<dynamic> investments = [];
  List<Account> savingsAccounts = [];
  List<Account> accounts = [];
  bool loading = true;

  // Tipos exibidos ao criar/aplicar em um investimento.
  static const _types = {
    'stock': ('Ações', Icons.show_chart),
    'reit': ('Fundos imobiliários', Icons.apartment),
    'etf': ('ETFs', Icons.stacked_line_chart),
    'fixed_income': ('Renda fixa', Icons.savings),
    'crypto': ('Criptomoedas', Icons.currency_bitcoin),
    'pension': ('Previdência', Icons.elderly),
    'other': ('Outros', Icons.more_horiz),
  };

  // Rotulos de tipos legados (para exibir investimentos antigos).
  static const _legacyTypes = {
    'savings': 'Poupança',
    'cdb': 'CDB',
    'lci_lca': 'LCI/LCA',
    'treasury': 'Tesouro Direto',
    'fund': 'Fundos',
  };

  static String _typeLabel(String? type) =>
      _types[type]?.$1 ?? _legacyTypes[type] ?? type ?? 'Outros';

  static IconData _typeIcon(String? type) =>
      _types[type]?.$2 ?? Icons.trending_up;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [iRes, aRes] = await Future.wait([
      ApiService.get('/investments'),
      ApiService.get('/accounts'),
    ]);
    setState(() {
      investments = ApiService.decode(iRes) is List
          ? ApiService.decode(iRes) as List
          : [];
      accounts = (ApiService.decode(aRes) as List)
          .map((e) => Account.fromJson(e))
          .toList();
      savingsAccounts = accounts.where((a) => a.type == 'savings').toList();
      loading = false;
    });
  }

  double get _totalCurrent =>
      investments.fold<double>(
        0,
        (s, i) => s + ((i['current_amount'] as num?)?.toDouble() ?? 0),
      ) +
      savingsAccounts.fold<double>(0, (s, a) => s + a.currentBalance);

  double get _totalInvested => investments.fold<double>(
        0,
        (s, i) => s + ((i['invested_amount'] as num?)?.toDouble() ?? 0),
      );

  // Aplica valor num tipo: cria o investimento se ainda nao existir,
  // senao faz um aporte. Em ambos os casos debita da conta escolhida.
  Future<void> _apply() async {
    if (accounts.where((a) => a.type != 'savings' && a.type != 'investment').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crie uma conta antes de aplicar.')),
      );
      return;
    }
    String type = 'cdb';
    int? accountId = accounts
        .firstWhere(
          (a) => a.type != 'savings' && a.type != 'investment',
          orElse: () => accounts.first,
        )
        .id;
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Aplicar em investimento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration:
                    const InputDecoration(labelText: 'Tipo de investimento'),
                items: _types.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Row(
                          children: [
                            Icon(e.value.$2, size: 20),
                            const SizedBox(width: 8),
                            Text(e.value.$1),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDialog(() => type = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: accountId,
                decoration:
                    const InputDecoration(labelText: 'Sair da conta'),
                items: accounts
                    .where(
                      (a) => a.type != 'savings' && a.type != 'investment',
                    )
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDialog(() => accountId = v),
              ),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Valor',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final amount = parseMoney(controller.text);
    if (amount == null || amount <= 0 || accountId == null) return;

    // Investimento existente do mesmo tipo? Aporte; senao cria.
    final existing = investments.firstWhere(
      (i) => i['type'] == type,
      orElse: () => null,
    );
    if (existing != null) {
      await ApiService.post('/investments/${existing['id']}/movements', {
        'kind': 'contribution',
        'amount': amount,
        'account_id': accountId,
      });
    } else {
      await ApiService.post('/investments', {
        'name': _types[type]!.$1,
        'type': type,
        'invested_amount': amount,
        'account_id': accountId,
        'debit_account': true,
      });
    }
    _load();
  }

  // Acoes sobre um investimento: renomear, rendimento, resgatar, excluir.
  Future<void> _openActions(dynamic inv) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${inv['name']}'),
              subtitle: Text(
                '${inv['type_label'] ?? ''} • atual R\$ ${fmtMoney(((inv['current_amount'] as num?)?.toDouble() ?? 0))}',
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.trending_up, color: Colors.green),
              title: const Text('Adicionar rendimento'),
              onTap: () {
                Navigator.pop(context);
                _yield(inv);
              },
            ),
            ListTile(
              leading: const Icon(Icons.money_off, color: Colors.orange),
              title: const Text('Resgatar para uma conta'),
              onTap: () {
                Navigator.pop(context);
                _withdraw(inv);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Renomear'),
              onTap: () {
                Navigator.pop(context);
                _rename(inv);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Excluir investimento'),
              onTap: () {
                Navigator.pop(context);
                _delete(inv);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _yield(dynamic inv) async {
    final controller = TextEditingController();
    final ok = await _valueDialog(
      'Rendimento em ${inv['name']}',
      controller,
      'Valor do rendimento',
    );
    if (!ok) return;
    final amount = parseMoney(controller.text);
    if (amount == null || amount <= 0) return;
    await ApiService.post('/investments/${inv['id']}/movements', {
      'kind': 'yield',
      'amount': amount,
    });
    _load();
  }

  Future<void> _withdraw(dynamic inv) async {
    final controller = TextEditingController();
    int? accountId = accounts
        .where((a) => a.type != 'investment')
        .map((a) => a.id)
        .firstOrNull;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Resgatar de ${inv['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: accountId,
                decoration:
                    const InputDecoration(labelText: 'Depositar na conta'),
                items: accounts
                    .where((a) => a.type != 'investment')
                    .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (v) => setDialog(() => accountId = v),
              ),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: InputDecoration(
                  labelText:
                      'Valor (até R\$ ${fmtMoney(((inv['current_amount'] as num?)?.toDouble() ?? 0))})',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resgatar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = parseMoney(controller.text);
    if (amount == null || amount <= 0 || accountId == null) return;
    final res = await ApiService.post(
      '/investments/${inv['id']}/movements',
      {'kind': 'withdrawal', 'amount': amount, 'account_id': accountId},
    );
    if (res.statusCode != 200 && res.statusCode != 201 && mounted) {
      final data = ApiService.decode(res);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data is Map ? data['error'] : 'Erro'}')),
      );
      return;
    }
    _load();
  }

  Future<void> _rename(dynamic inv) async {
    final controller = TextEditingController(text: '${inv['name']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear investimento'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nome'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    await ApiService.put('/investments/${inv['id']}', {
      'name': controller.text.trim(),
    });
    _load();
  }

  Future<void> _delete(dynamic inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir ${inv['name']}?'),
        content: const Text(
          'O investimento será removido. Os lançamentos nas contas são mantidos.',
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
    if (confirmed != true) return;
    await ApiService.delete('/investments/${inv['id']}');
    _load();
  }

  Future<bool> _valueDialog(
    String title,
    TextEditingController controller,
    String label,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [MoneyInputFormatter()],
          decoration: InputDecoration(labelText: label, prefixText: 'R\$ '),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final profit = _totalCurrent - _totalInvested;
    return Scaffold(
      appBar: AppBar(title: const Text('Investimentos')),
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total investido',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'R\$ ${fmtMoney(_totalCurrent)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Rendimento acumulado: '
                                '${profit >= 0 ? '+' : ''}R\$ ${fmtMoney(profit)}',
                                style: TextStyle(
                                  color: profit >= 0
                                      ? Colors.green.shade700
                                      : Theme.of(context).colorScheme.error,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...savingsAccounts.map(
                        (a) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.savings),
                          ),
                          title: Text(a.name),
                          subtitle: const Text('Poupança (conta)'),
                          trailing: Text(
                            'R\$ ${fmtMoney(a.currentBalance)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      ...investments.map((inv) {
                        final type = '${inv['type']}';
                        final icon = _typeIcon(type);
                        final current =
                            (inv['current_amount'] as num?)?.toDouble() ?? 0;
                        final invProfit =
                            (inv['profit'] as num?)?.toDouble() ?? 0;
                        return ListTile(
                          onTap: () => _openActions(inv),
                          leading: CircleAvatar(child: Icon(icon)),
                          title: Text('${inv['name']}'),
                          subtitle: Text(
                            '${inv['type_label'] ?? _typeLabel(type)} • '
                            '${invProfit >= 0 ? '+' : ''}R\$ ${fmtMoney(invProfit)}',
                          ),
                          trailing: Text(
                            'R\$ ${fmtMoney(current)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }),
                      if (investments.isEmpty && savingsAccounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'Nenhum investimento ainda.\n'
                              'Toque em + para aplicar um valor da sua conta.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'investments_fab',
        onPressed: _apply,
        child: const Icon(Icons.add),
      ),
    );
  }
}
