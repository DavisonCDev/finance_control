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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar débito'),
        content: Text(
          'A recorrência "${r['description'] ?? ''}" de R\$ ${fmtMoney((r['amount'] as num))} prevista para ${fmtDate(r['next_date'])} foi realizada?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim, debitar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.post('/recurring/${r['id']}/generate', {});
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Débito confirmado')));
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
                  if (accounts.isNotEmpty)
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
                      accountId == null ||
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
                    'account_id': accountId,
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
                    if (mounted) Navigator.pop(context);
                    _load();
                  } else {
                    if (mounted) {
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
    final [aRes, cRes] = await Future.wait([
      ApiService.get('/accounts'),
      ApiService.get('/categories'),
    ]);
    setState(() {
      accounts = (ApiService.decode(aRes) as List)
          .map((e) => Account.fromJson(e))
          .toList();
      categories = (ApiService.decode(cRes) as List)
          .map((e) => Category.fromJson(e))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações recorrentes'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final r = items[i];
                final isDue =
                    DateTime.tryParse(
                      r['next_date'] ?? '',
                    )?.isBefore(DateTime.now().add(const Duration(days: 1))) ??
                    false;
                return ListTile(
                  title: Text(r['description'] ?? 'Recorrente'),
                  subtitle: Text(
                    'R\$ ${fmtMoney((r['amount'] as num))} • Próxima: ${fmtDate(r['next_date'])}\n'
                    '${r['account_name'] ?? ''} • ${r['category_name'] ?? ''}',
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
                        child: isDue
                            ? const Text('Confirmar')
                            : const Text('Gerar'),
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
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'recurring_fab',
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}
