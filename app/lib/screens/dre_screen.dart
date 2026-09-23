import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'dre_detailed_screen.dart';

class DREScreen extends StatefulWidget {
  const DREScreen({super.key});

  @override
  State<DREScreen> createState() => _DREScreenState();
}

class _DREScreenState extends State<DREScreen> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  int year = DateTime.now().year;
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final monthLabels = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];

  final Set<String> calcKeys = {'margem_contribuicao', 'lucro_prejuizo', 'ebtida'};
  final Set<String> negativeKeys = {'custos', 'despesas', 'impostos', 'investimentos'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiService.get('/reports/dre-yearly?year=$year');
      setState(() {
        data = ApiService.decode(res) as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Não foi possível carregar a DRE. $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from(data['lines'] as List? ?? []);
    final receitas = lines.firstWhere(
      (l) => l['key'] == 'receitas_operacionais',
      orElse: () => {'per_month': List.filled(13, 0.0)},
    );
    final lucro = lines.firstWhere(
      (l) => l['key'] == 'lucro_prejuizo',
      orElse: () => {'per_month': List.filled(13, 0.0)},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado do ano'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Resultado por grupo',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DREDetailedScreen()),
            ),
          ),
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
                        'Resultado $year',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (error != null) Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
                      ),
                      _buildSummary(lines),
                      const SizedBox(height: 16),
                      _buildChart(receitas, lucro),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 12,
                              horizontalMargin: 4,
                              columns: [
                                const DataColumn(label: Text('Conta')),
                                ...['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez']
                                    .map((m) => DataColumn(label: Text(m, textAlign: TextAlign.right))),
                                const DataColumn(label: Text('Total Ano', textAlign: TextAlign.right)),
                              ],
                              rows: lines.map((line) {
                                final isCalc = line['is_calc'] == true;
                                final isNegative = negativeKeys.contains(line['key']);
                                final isPositiveHighlight = calcKeys.contains(line['key']) || line['key'] == 'receitas_operacionais';
                                final color = isCalc
                                    ? (line['key'] == 'lucro_prejuizo' ? Colors.blue : Colors.teal)
                                    : (isNegative ? Colors.red : Colors.black87);
                                final perMonth = List<num>.from(line['per_month'] as List? ?? List.filled(13, 0));
                                return DataRow(
                                  color: WidgetStateProperty.resolveWith<Color?>((s) {
                                    if (isPositiveHighlight) return Colors.grey.shade50;
                                    return null;
                                  }),
                                  cells: [
                                    DataCell(Text(
                                      (line['label'] ?? '').toString(),
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: isCalc ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    )),
                                    ...List.generate(12, (i) {
                                      final v = (i + 1 < perMonth.length ? perMonth[i + 1] : 0).toDouble();
                                      return DataCell(Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          money.format(v),
                                          style: TextStyle(
                                            color: isNegative && v > 0 ? Colors.red : (v < 0 ? Colors.red : (v > 0 && !isNegative ? Colors.green : Colors.black87)),
                                            fontWeight: isCalc ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ));
                                    }),
                                    DataCell(Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        money.format((perMonth.isNotEmpty ? perMonth[0] : 0).toDouble()),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    )),
                                  ],
                                );
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

  Widget _buildSummary(List<Map<String, dynamic>> lines) {
    double receitas = 0, custos = 0, despesas = 0, impostos = 0, investimentos = 0, lucro = 0, margem = 0;
    for (var l in lines) {
      final k = l['key'];
      final per = List<num>.from(l['per_month'] as List? ?? []);
      final v = per.isNotEmpty ? per[0].toDouble() : 0.0;
      if (k == 'receitas_operacionais') receitas = v;
      if (k == 'custos') custos = v;
      if (k == 'despesas') despesas = v;
      if (k == 'impostos') impostos = v;
      if (k == 'investimentos') investimentos = v;
      if (k == 'lucro_prejuizo') lucro = v;
      if (k == 'margem_contribuicao') margem = v;
    }
    final double lucMargem = receitas > 0 ? (margem / receitas) * 100 : 0.0;
    final double lucrat = receitas > 0 ? (lucro / receitas) * 100 : 0.0;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _sumCard('Receitas Oper.', receitas, Colors.green, Icons.trending_up),
        _sumCard('Custos', custos, Colors.red, Icons.inventory_2),
        _sumCard('Margem Contrib.', margem, Colors.teal, Icons.insights),
        _sumCard('Margem %', lucMargem, Colors.teal, Icons.percent, isPercent: true),
        _sumCard('Despesas', despesas, Colors.red, Icons.receipt_long),
        _sumCard('Impostos', impostos, Colors.deepOrange, Icons.receipt),
        _sumCard('Lucro / Prej.', lucro, lucro >= 0 ? Colors.blue : Colors.red, Icons.account_balance_wallet),
        _sumCard('Lucratividade %', lucrat, Colors.blue, Icons.show_chart, isPercent: true),
        _sumCard('Investimentos', investimentos, Colors.deepPurple, Icons.trending_up),
      ],
    );
  }

  Widget _sumCard(String title, double value, Color color, IconData icon, {bool isPercent = false}) {
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isPercent ? '${value.toStringAsFixed(1)}%' : money.format(value),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(Map<String, dynamic> receitas, Map<String, dynamic> lucro) {
    final rPer = List<num>.from(receitas['per_month'] as List? ?? List.filled(13, 0));
    final lPer = List<num>.from(lucro['per_month'] as List? ?? List.filled(13, 0));
    return SizedBox(
      height: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 80)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(v.toInt() >= 1 && v.toInt() <= 12 ? monthLabels[v.toInt() - 1] : ''),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: const FlGridData(show: true),
              barGroups: List.generate(12, (i) {
                final idx = i + 1;
                return BarChartGroupData(
                  x: idx,
                  barRods: [
                    BarChartRodData(toY: (idx < rPer.length ? rPer[idx] : 0).toDouble(), color: Colors.green, width: 8),
                    BarChartRodData(toY: (idx < lPer.length ? lPer[idx] : 0).toDouble(), color: Colors.blue, width: 8),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
