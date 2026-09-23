import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';

class GoalsMonthlyScreen extends StatefulWidget {
  const GoalsMonthlyScreen({super.key});

  @override
  State<GoalsMonthlyScreen> createState() => _GoalsMonthlyScreenState();
}

class _GoalsMonthlyScreenState extends State<GoalsMonthlyScreen> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  int year = DateTime.now().year;
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final percent = NumberFormat.decimalPercentPattern(locale: 'pt_BR', decimalDigits: 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiService.get('/reports/goals-yearly?year=$year');
      setState(() {
        data = ApiService.decode(res) as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Não foi possível carregar as metas. $e';
        loading = false;
      });
    }
  }

  Future<void> _saveGoal(String goalType) async {
    final block = data[goalType] ?? {};
    final months = (block['months'] as List? ?? []).map<double>((m) {
      return (m['target'] as num? ?? 0).toDouble();
    }).toList();
    try {
      final res = await ApiService.put('/reports/goals-yearly', {
        'year': year,
        'goal_type': goalType,
        'months': months,
      });
      if (res.statusCode >= 400) throw Exception(ApiService.decode(res)['error'] ?? 'Erro');
      setState(() { data = ApiService.decode(res) as Map<String, dynamic>; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metas salvas com sucesso.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  void _editTargets(String goalType, String title) {
    final block = data[goalType] ?? {};
    final months = List<Map<String, dynamic>>.from(block['months'] as List? ?? []);
    final tmp = List<double>.generate(12, (i) => (months[i]['target'] as num? ?? 0).toDouble());
    final labels = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialog) => AlertDialog(
          title: Text('Editar metas de $title'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(12, (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 48, child: Text(labels[i])),
                      Expanded(
                        child: TextFormField(
                          initialValue: fmtMoney(tmp[i]),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [MoneyInputFormatter()],
                          onChanged: (v) => tmp[i] = parseMoney(v) ?? 0,
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixText: 'R\$ ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final block = data[goalType] ?? {};
                final ms = block['months'] as List? ?? [];
                for (var i = 0; i < 12; i++) {
                  if (ms.length > i) (ms[i] as Map)['target'] = tmp[i];
                }
                (block as Map)['total'] = {
                  'target': tmp.reduce((a, b) => a + b),
                  'realized': (block['total'] as Map? ?? {})['realized'] ?? 0,
                };
                setState(() {});
                Navigator.pop(ctx);
                await _saveGoal(goalType);
              },
              child: const Text('Salvar'),
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
        title: const Text('Metas Mensais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar),
            tooltip: 'Selecionar ano',
            onPressed: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (ctx) {
                  int sel = year;
                  return StatefulBuilder(
                    builder: (ctx2, setD) => AlertDialog(
                      title: const Text('Ano'),
                      content: DropdownButton<int>(
                        value: sel,
                        items: List.generate(6, (i) => DateTime.now().year - 2 + i)
                            .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                            .toList(),
                        onChanged: (v) { if (v != null) { sel = v; setD(() {}); } },
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('OK')),
                      ],
                    ),
                  );
                },
              );
              if (picked != null) { year = picked; await _load(); }
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ano $year',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (error != null) Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(error!),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildBlock('receitas', 'Receitas', Colors.green),
                      const SizedBox(height: 16),
                      _buildBlock('despesas', 'Despesas', Colors.red),
                      const SizedBox(height: 16),
                      _buildBlock('resultado', 'Resultado', Colors.blue),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBlock(String key, String title, Color color) {
    final block = data[key] as Map<String, dynamic>? ?? {};
    final months = List<Map<String, dynamic>>.from(block['months'] as List? ?? []);
    final total = Map<String, dynamic>.from(block['total'] as Map? ?? {});
    final parcial = Map<String, dynamic>.from(block['parcial'] as Map? ?? {});

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4, height: 24,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Editar metas de $title',
                  onPressed: () => _editTargets(key, title),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                horizontalMargin: 4,
                columns: [
                  const DataColumn(label: Text('Campo')),
                  ...['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez']
                      .map((m) => DataColumn(label: Text(m, textAlign: TextAlign.right))),
                  const DataColumn(label: Text('Total', textAlign: TextAlign.right)),
                  const DataColumn(label: Text('Parcial', textAlign: TextAlign.right)),
                ],
                rows: [
                  DataRow(cells: [
                    const DataCell(Text('Meta')),
                    ...List.generate(12, (i) => DataCell(Align(
                      alignment: Alignment.centerRight,
                      child: Text(money.format(months.length > i ? (months[i]['target'] as num? ?? 0) : 0)),
                    ))),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      money.format(total['target'] as num? ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ))),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      money.format(parcial['target'] as num? ?? 0),
                    ))),
                  ]),
                  DataRow(cells: [
                    const DataCell(Text('Realizado')),
                    ...List.generate(12, (i) => DataCell(Align(
                      alignment: Alignment.centerRight,
                      child: Text(money.format(months.length > i ? (months[i]['realized'] as num? ?? 0) : 0)),
                    ))),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      money.format(total['realized'] as num? ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ))),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      money.format(parcial['realized'] as num? ?? 0),
                    ))),
                  ]),
                  DataRow(cells: [
                    const DataCell(Text('% Diferença')),
                    ...List.generate(12, (i) {
                      final v = months.length > i ? (months[i]['difference_percent'] as num? ?? 0) : 0;
                      return DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${v.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: (v as num) >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ));
                    }),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      '${(total['difference_percent'] as num? ?? 0).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: ((total['difference_percent'] as num? ?? 0)) >= 0 ? Colors.green : Colors.red,
                      ),
                    ))),
                    DataCell(Align(alignment: Alignment.centerRight, child: Text(
                      '${(parcial['difference_percent'] as num? ?? 0).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: ((parcial['difference_percent'] as num? ?? 0)) >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ))),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
