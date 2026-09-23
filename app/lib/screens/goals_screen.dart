import 'package:flutter/material.dart';
import '../models/goal.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../models/account.dart';
import '../utils/formatters.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Goal> goals = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/goals');
    setState(() {
      goals = (ApiService.decode(res) as List)
          .map((e) => Goal.fromJson(e))
          .toList();
      loading = false;
    });
  }

  Future<void> _openGoal(Goal goal) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    List<Account> accounts = [];
    List<dynamic> contributions = [];
    int? selectedAccountId;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(goal.name),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alvo: R\$ ${fmtMoney(goal.targetAmount)}'),
                  Text('Atual: R\$ ${fmtMoney(goal.currentAmount)}'),
                  Text('${goal.percent.toStringAsFixed(1)}%'),
                  LinearProgressIndicator(value: goal.percent / 100),
                  const Divider(),
                  const Text(
                    'Novo aporte',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Observação'),
                  ),
                  FutureBuilder(
                    future: ApiService.get('/accounts'),
                    builder: (_, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final data = ApiService.decode(snap.data!) as List? ?? [];
                      accounts = data.map((e) => Account.fromJson(e)).toList();
                      return DropdownButtonFormField<int?>(
                        initialValue: selectedAccountId,
                        hint: const Text('Conta de origem (opcional)'),
                        decoration: const InputDecoration(labelText: 'Conta'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Nenhuma (sem débito)'),
                          ),
                          ...accounts.map<DropdownMenuItem<int?>>(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setStateDialog(() => selectedAccountId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final amount = parseMoney(amountController.text) ?? 0;
                        if (amount <= 0) return;
                        final body = <String, dynamic>{
                          'amount': amount,
                          'notes': notesController.text,
                        };
                        if (selectedAccountId != null) {
                          body['account_id'] = selectedAccountId!;
                        }
                        final res = await ApiService.post(
                          '/goals/${goal.id}/contributions',
                          body,
                        );
                        if (res.statusCode == 201) {
                          if (mounted) Navigator.pop(context);
                          _load();
                          _showContributions(goal);
                        } else {
                          final msg =
                              ApiService.decode(res)['error'] ?? res.body;
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro: $msg')),
                            );
                          }
                        }
                      },
                      child: const Text('Aportar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showContributions(goal);
              },
              child: const Text('Ver aportes'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContributions(Goal goal) async {
    final res = await ApiService.get('/goals/${goal.id}/contributions');
    final contributions = (ApiService.decode(res) as List? ?? []);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aportes - ${goal.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: contributions.isEmpty
              ? const Text('Nenhum aporte ainda.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: contributions.length,
                  itemBuilder: (_, i) {
                    final c = contributions[i];
                    return ListTile(
                      title: Text(
                        'R\$ ${fmtMoney((c['amount'] ?? 0))}',
                      ),
                      subtitle: Text(fmtDate(c['date'])),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Goal goal) async {
    int? selectedAccountId;
    List<Account> accounts = [];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Excluir meta?'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goal.currentAmount > 0)
                  Text(
                    'A meta tem R\$ ${fmtMoney(goal.currentAmount)} acumulados. Selecione a conta de destino para resgatar o valor.',
                  )
                else
                  const Text(
                    'Todos os aportes serão perdidos. Essa ação não pode ser desfeita.',
                  ),
                if (goal.currentAmount > 0)
                  FutureBuilder(
                    future: ApiService.get('/accounts'),
                    builder: (_, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final data = ApiService.decode(snap.data!) as List? ?? [];
                      accounts = data.map((e) => Account.fromJson(e)).toList();
                      return DropdownButtonFormField<int?>(
                        initialValue: selectedAccountId,
                        hint: const Text('Conta de destino'),
                        decoration: const InputDecoration(labelText: 'Conta'),
                        items: accounts
                            .map<DropdownMenuItem<int?>>(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(a.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setStateDialog(() => selectedAccountId = v),
                      );
                    },
                  ),
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
              child: const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final body = goal.currentAmount > 0 && selectedAccountId != null
        ? {'account_id': selectedAccountId!}
        : null;
    final res = await ApiService.delete('/goals/${goal.id}', body);
    if (res.statusCode == 200) {
      _load();
    } else {
      final decoded = ApiService.decode(res);
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? res.body)
          : res.body;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    }
  }

  Future<void> _openForm({Goal? goal}) async {
    final isEditing = goal != null;
    final nameController = TextEditingController(
      text: isEditing ? goal.name : '',
    );
    final targetController = TextEditingController(
      text: isEditing ? fmtMoney(goal.targetAmount) : '',
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar meta' : 'Nova meta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome da meta'),
            ),
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Valor alvo',
                prefixText: 'R\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final body = {
                'name': nameController.text,
                'target_amount': parseMoney(targetController.text) ?? 0,
              };
              if (isEditing) {
                await ApiService.put('/goals/${goal.id}', body);
              } else {
                await ApiService.post('/goals', body);
              }
              if (mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas financeiras'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: goals.length,
              itemBuilder: (_, i) {
                final g = goals[i];
                return ListTile(
                  onTap: () => _openGoal(g),
                  leading: const Icon(Icons.flag),
                  title: Text(g.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: g.percent / 100),
                      Text(
                        'R\$ ${fmtMoney(g.currentAmount)} de R\$ ${fmtMoney(g.targetAmount)}',
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${g.percent.toStringAsFixed(0)}%'),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openForm(goal: g),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _confirmDelete(g),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'goals_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
