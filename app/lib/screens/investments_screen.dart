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
  final Map<int, List<dynamic>> _movements = {};
  final Set<int> _loadingMovements = {};

  // Tipos exibidos ao criar uma caixinha/investimento.
  static const _types = {
    'fund': ('Caixinha / Fundos', Icons.inventory_2_outlined),
    'fixed_income': ('Renda fixa', Icons.savings),
    'stock': ('Ações', Icons.show_chart),
    'reit': ('Fundos imobiliários', Icons.apartment),
    'etf': ('ETFs', Icons.stacked_line_chart),
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
  };

  static String _typeLabel(String? type) =>
      _types[type]?.$1 ?? _legacyTypes[type] ?? type ?? 'Outros';

  static IconData _typeIcon(String? type) =>
      _types[type]?.$2 ?? Icons.trending_up;

  static (IconData, Color, String) _movementStyle(String kind) {
    switch (kind) {
      case 'contribution':
        return (Icons.add_circle_outline, Colors.green.shade700, '+');
      case 'withdrawal':
        return (Icons.remove_circle_outline, Colors.orange.shade800, '-');
      case 'dividend':
      case 'yield':
        return (Icons.trending_up, Colors.green.shade700, '+');
      case 'fee':
      case 'tax':
        return (Icons.money_off, Colors.red.shade700, '-');
      default:
        return (Icons.price_change, Colors.blueGrey, '=');
    }
  }

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

  Future<void> _loadMovements(int id) async {
    if (_loadingMovements.contains(id)) return;
    setState(() => _loadingMovements.add(id));
    final res = await ApiService.get('/investments/$id');
    final data = ApiService.decode(res);
    setState(() {
      _loadingMovements.remove(id);
      _movements[id] = data is Map && data['movements'] is List
          ? (data['movements'] as List).reversed.toList()
          : [];
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

  List<Account> get _debitableAccounts => accounts
      .where((a) => a.type != 'savings' && a.type != 'investment')
      .toList();

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Widget _dateTile(DateTime date, void Function(void Function()) setDialog) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today, size: 20),
      title: const Text('Data'),
      subtitle: Text(fmtDate(date)),
      onTap: () async {
        final d = await _pickDate(date);
        if (d != null) setDialog(() => date = d);
      },
    );
  }

  // + : nova caixinha, aporte, resgate ou rendimento.
  Future<void> _openAdd() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Nova caixinha'),
              subtitle: const Text('Cria um fundo separado (reserva, viagem...)'),
              onTap: () => Navigator.pop(context, 'box'),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: Colors.green.shade700),
              title: const Text('Aporte'),
              subtitle: const Text('Aplica dinheiro de uma conta'),
              onTap: () => Navigator.pop(context, 'contribution'),
            ),
            ListTile(
              leading: Icon(Icons.money_off, color: Colors.orange.shade800),
              title: const Text('Resgate'),
              subtitle: const Text('Retira dinheiro para uma conta'),
              onTap: () => Navigator.pop(context, 'withdrawal'),
            ),
            ListTile(
              leading: Icon(Icons.trending_up, color: Colors.green.shade700),
              title: const Text('Rendimento'),
              subtitle: const Text('Lança rendimento ou provento'),
              onTap: () => Navigator.pop(context, 'yield'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'box') {
      await _createBox();
      return;
    }
    final inv = await _pickInvestment();
    if (inv == null) return;
    switch (action) {
      case 'contribution':
        await _contribute(inv);
      case 'withdrawal':
        await _withdraw(inv);
      case 'yield':
        await _yield(inv);
    }
  }

  Future<dynamic> _pickInvestment() async {
    if (investments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crie uma caixinha primeiro.')),
      );
      return null;
    }
    if (investments.length == 1) return investments.first;
    return showModalBottomSheet<dynamic>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: investments
              .map(
                (inv) => ListTile(
                  leading: CircleAvatar(
                    child: Icon(_typeIcon('${inv['type']}')),
                  ),
                  title: Text('${inv['name']}'),
                  subtitle: Text(
                    'R\$ ${fmtMoney((inv['current_amount'] as num?)?.toDouble() ?? 0)}',
                  ),
                  onTap: () => Navigator.pop(context, inv),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  // Nova caixinha: fundo com nome proprio; valor inicial opcional.
  Future<void> _createBox() async {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    String type = 'fund';
    DateTime date = DateTime.now();
    int? accountId = _debitableAccounts.map((a) => a.id).firstOrNull;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Nova caixinha'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome (ex.: Reserva, Viagem)',
                  ),
                  autofocus: true,
                ),
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
                TextField(
                  controller: valueController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor inicial (opcional)',
                    prefixText: 'R\$ ',
                  ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: accountId,
                  decoration:
                      const InputDecoration(labelText: 'Sair da conta'),
                  items: _debitableAccounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => accountId = v),
                ),
                _dateTile(date, setDialog),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) return;
    final amount = parseMoney(valueController.text) ?? 0;
    if (amount > 0 && accountId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escolha a conta de onde sai o valor inicial.'),
          ),
        );
      }
      return;
    }

    await ApiService.post('/investments', {
      'name': name,
      'type': type,
      'invested_amount': amount,
      'account_id': amount > 0 ? accountId : null,
      'debit_account': amount > 0,
      'purchase_date': date.toIso8601String().substring(0, 10),
    });
    _load();
  }

  Future<void> _contribute(dynamic inv) async {
    if (_debitableAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crie uma conta antes de aplicar.')),
      );
      return;
    }
    final controller = TextEditingController();
    int? accountId = _debitableAccounts.first.id;
    DateTime date = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Aporte em ${inv['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$ ',
                ),
                autofocus: true,
              ),
              DropdownButtonFormField<int>(
                initialValue: accountId,
                decoration:
                    const InputDecoration(labelText: 'Sair da conta'),
                items: _debitableAccounts
                    .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (v) => setDialog(() => accountId = v),
              ),
              _dateTile(date, setDialog),
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
    await ApiService.post('/investments/${inv['id']}/movements', {
      'kind': 'contribution',
      'amount': amount,
      'account_id': accountId,
      'date': date.toIso8601String().substring(0, 10),
    });
    _movements.remove(inv['id']);
    _load();
    _loadMovements(inv['id']);
  }

  Future<void> _yield(dynamic inv) async {
    final controller = TextEditingController();
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Rendimento em ${inv['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Valor do rendimento',
                  prefixText: 'R\$ ',
                ),
                autofocus: true,
              ),
              _dateTile(date, setDialog),
            ],
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
      ),
    );
    if (ok != true) return;
    final amount = parseMoney(controller.text);
    if (amount == null || amount <= 0) return;
    await ApiService.post('/investments/${inv['id']}/movements', {
      'kind': 'yield',
      'amount': amount,
      'date': date.toIso8601String().substring(0, 10),
    });
    _movements.remove(inv['id']);
    _load();
    _loadMovements(inv['id']);
  }

  Future<void> _withdraw(dynamic inv) async {
    final controller = TextEditingController();
    int? accountId =
        accounts.where((a) => a.type != 'investment').map((a) => a.id).firstOrNull;
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Resgatar de ${inv['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                autofocus: true,
              ),
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
              _dateTile(date, setDialog),
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
      {
        'kind': 'withdrawal',
        'amount': amount,
        'account_id': accountId,
        'date': date.toIso8601String().substring(0, 10),
      },
    );
    if (res.statusCode != 200 && res.statusCode != 201 && mounted) {
      final data = ApiService.decode(res);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data is Map ? data['error'] : 'Erro'}')),
      );
      return;
    }
    _movements.remove(inv['id']);
    _load();
    _loadMovements(inv['id']);
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
          'O investimento e todo o histórico de movimentações serão removidos. '
          'Os lançamentos nas contas são mantidos.',
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

  Widget _movementTile(dynamic m) {
    final (icon, color, sign) = _movementStyle('${m['kind']}');
    final notes = '${m['notes'] ?? ''}'.trim();
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text('${m['kind_label'] ?? m['kind']}'),
      subtitle: Text(
        notes.isEmpty
            ? fmtDate(m['date'])
            : '${fmtDate(m['date'])} • $notes',
      ),
      trailing: Text(
        '${sign}R\$ ${fmtMoney((m['amount'] as num?)?.toDouble() ?? 0)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _investmentTile(dynamic inv) {
    final id = inv['id'] as int;
    final current = (inv['current_amount'] as num?)?.toDouble() ?? 0;
    final invProfit = (inv['profit'] as num?)?.toDouble() ?? 0;
    final movements = _movements[id];

    return ExpansionTile(
      leading: CircleAvatar(child: Icon(_typeIcon('${inv['type']}'))),
      title: Text('${inv['name']}'),
      subtitle: Text(
        '${inv['type_label'] ?? _typeLabel('${inv['type']}')} • '
        '${invProfit >= 0 ? '+' : ''}R\$ ${fmtMoney(invProfit)}',
      ),
      trailing: Text(
        'R\$ ${fmtMoney(current)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onExpansionChanged: (open) {
        if (open) _loadMovements(id);
      },
      children: [
        if (_loadingMovements.contains(id))
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (movements == null || movements.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Sem movimentações.'),
          )
        else
          ...movements.map(_movementTile),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Aporte'),
              onPressed: () => _contribute(inv),
            ),
            TextButton.icon(
              icon: const Icon(Icons.trending_up, size: 18),
              label: const Text('Rendimento'),
              onPressed: () => _yield(inv),
            ),
            TextButton.icon(
              icon: const Icon(Icons.money_off, size: 18),
              label: const Text('Resgatar'),
              onPressed: () => _withdraw(inv),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'rename') _rename(inv);
                if (v == 'delete') _delete(inv);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Renomear')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
      ],
    );
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
                      ...investments.map(_investmentTile),
                      if (investments.isEmpty && savingsAccounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'Nenhum investimento ainda.\n'
                              'Toque em + para criar uma caixinha ou aplicar.',
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
        onPressed: _openAdd,
        child: const Icon(Icons.add),
      ),
    );
  }
}
