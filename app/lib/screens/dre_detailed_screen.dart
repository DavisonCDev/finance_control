import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class DREDetailedScreen extends StatefulWidget {
  final String? initialGroup;
  const DREDetailedScreen({super.key, this.initialGroup});

  @override
  State<DREDetailedScreen> createState() => _DREDetailedScreenState();
}

class _DREDetailedScreenState extends State<DREDetailedScreen> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  int year = DateTime.now().year;
  String? selectedGroup;

  final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static const Map<String, String> _groupLabels = {
    'Receita1': 'Receitas fixas',
    'Receita2': 'Receitas variáveis',
    'Receita3': 'Outras receitas',
    'Receita4': 'Outras receitas 2',
    'Custo1': 'Despesas variáveis 1',
    'Custo2': 'Despesas variáveis 2',
    'Custo3': 'Despesas variáveis 3',
    'Despesa1': 'Despesas fixas',
    'Despesa2': 'Despesas variáveis — outros',
    'Despesa3': 'Despesas extras 1',
    'Despesa4': 'Despesas extras 2',
    'Despesa5': 'Despesas extras 3',
    'Imposto': 'Impostos',
    'Investimento': 'Investimentos',
  };

  List<MapEntry<String?, String>> get groupOptions => [
    const MapEntry(null, 'Todos os grupos'),
    ..._groupLabels.entries.map(
      (e) => MapEntry<String?, String>(e.key, e.value),
    ),
  ];

  @override
  void initState() {
    super.initState();
    selectedGroup = widget.initialGroup;
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final qp = StringBuffer('/reports/dre-detailed?year=$year');
      if (selectedGroup != null) qp.write('&pc_group=${Uri.encodeComponent(selectedGroup!)}');
      final res = await ApiService.get(qp.toString());
      setState(() {
        data = ApiService.decode(res) as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Não foi possível carregar o resultado detalhado. $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado por grupo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
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
                constraints: const BoxConstraints(maxWidth: 1400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resultado por grupo $year',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Text('Grupo: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  initialValue: selectedGroup,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  items: groupOptions
                                      .map((e) => DropdownMenuItem<String?>(
                                            value: e.key,
                                            child: Text(e.value),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    selectedGroup = v;
                                    _load();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('${items.length} itens'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (error != null) Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: items.isEmpty
                              ? const ListTile(
                                  leading: Icon(Icons.info_outline),
                                  title: Text('Nenhum item encontrado.'),
                                  subtitle: Text('Selecione outro grupo ou ano, ou cadastre transações.'),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columnSpacing: 12,
                                    horizontalMargin: 4,
                                    columns: [
                                      const DataColumn(label: Text('Cód. PC')),
                                      const DataColumn(label: Text('Item')),
                                      const DataColumn(label: Text('Grupo')),
                                      ...['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez']
                                          .map((m) => DataColumn(label: Text(m, textAlign: TextAlign.right))),
                                      const DataColumn(label: Text('Total', textAlign: TextAlign.right)),
                                    ],
                                    rows: items.map((it) {
                                      final perMonth = List<num>.from(it['per_month'] as List? ?? List.filled(13, 0));
                                      return DataRow(cells: [
                                        DataCell(Text(
                                          (it['pc_code'] ?? '').toString(),
                                          style: const TextStyle(fontFamily: 'monospace'),
                                        )),
                                        DataCell(Text((it['name'] ?? '').toString())),
                                        DataCell(Text(
                                          _groupLabels[(it['pc_group'] ?? '').toString()] ?? (it['pc_group'] ?? '').toString(),
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        )),
                                        ...List.generate(12, (i) {
                                          final v = ((i + 1) < perMonth.length ? perMonth[i + 1] : 0).toDouble();
                                          return DataCell(Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              money.format(v),
                                              style: TextStyle(
                                                color: v < 0 ? Colors.red : (v > 0 ? Colors.green.shade800 : null),
                                              ),
                                            ),
                                          ));
                                        }),
                                        DataCell(Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            money.format((perMonth.isNotEmpty ? perMonth[0] : 0).toDouble()),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        )),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
