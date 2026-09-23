import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class CashflowYearlyScreen extends StatefulWidget {
  const CashflowYearlyScreen({super.key});

  @override
  State<CashflowYearlyScreen> createState() => _CashflowYearlyScreenState();
}

class _CashflowYearlyScreenState extends State<CashflowYearlyScreen> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  int year = DateTime.now().year;
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final monthLabels = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiService.get('/reports/cashflow-yearly?year=$year');
      setState(() {
        data = ApiService.decode(res) as Map<String, dynamic>;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Não foi possível carregar o fluxo de caixa. $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = List<Map<String, dynamic>>.from(data['months'] as List? ?? []);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo de Caixa'),
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
                        'Fluxo de Caixa $year',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (error != null) Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
                      ),
                      _buildSummary(months),
                      const SizedBox(height: 16),
                      _buildChart(months),
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
                                const DataColumn(label: Text('Campo')),
                                ...['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez']
                                    .map((m) => DataColumn(label: Text(m, textAlign: TextAlign.right))),
                                const DataColumn(label: Text('Total/Ano', textAlign: TextAlign.right)),
                              ],
                              rows: [
                                _buildRow('Saldo Inicial', months, 'initial_balance', false),
                                _buildRow('Receitas (pagas)', months, 'income_paid', false, positive: true),
                                _buildRow('Despesas (pagas)', months, 'expense_paid', false, negative: true),
                                _buildRow('Lucro / Prejuízo', months, 'profit', true),
                                _buildRow('Saldo Acumulado', months, 'accumulated', true),
                                _buildRow('Lucratividade (%)', months, 'profitability', false, isPercent: true),
                                _buildRow('Contas a Receber', months, 'accounts_receivable', false, positive: true),
                                _buildRow('Contas a Pagar', months, 'accounts_payable', false, negative: true),
                                _buildRow('Necessidade de Caixa', months, 'cash_need', true),
                              ],
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

  Widget _buildSummary(List<Map<String, dynamic>> months) {
    double totalReceitas = 0, totalDespesas = 0, totalLucro = 0, acumulado = 0, receber = 0, pagar = 0;
    for (var m in months) {
      totalReceitas += (m['income_paid'] as num? ?? 0).toDouble();
      totalDespesas += (m['expense_paid'] as num? ?? 0).toDouble();
      receber += (m['accounts_receivable'] as num? ?? 0).toDouble();
      pagar += (m['accounts_payable'] as num? ?? 0).toDouble();
    }
    totalLucro = totalReceitas - totalDespesas;
    if (months.isNotEmpty) acumulado = (months.last['accumulated'] as num? ?? 0).toDouble();
    final lucratividade = totalReceitas > 0 ? (totalLucro / totalReceitas) * 100 : 0.0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _sumCard('Saldo Acumulado', acumulado, Colors.blue, Icons.account_balance_wallet),
        _sumCard('Receitas Ano', totalReceitas, Colors.green, Icons.trending_up),
        _sumCard('Despesas Ano', totalDespesas, Colors.red, Icons.trending_down),
        _sumCard('Lucro / Prejuízo', totalLucro, totalLucro >= 0 ? Colors.green : Colors.red, Icons.payments),
        _sumCard('Lucratividade', lucratividade, Colors.teal, Icons.percent, isPercent: true),
        _sumCard('Contas a Receber', receber, Colors.lightGreen, Icons.schedule_send),
        _sumCard('Contas a Pagar', pagar, Colors.deepOrange, Icons.schedule),
        _sumCard('Nec. Caixa', receber - pagar, (receber - pagar) >= 0 ? Colors.green : Colors.red, Icons.warning_amber),
      ],
    );
  }

  Widget _sumCard(String title, double value, Color color, IconData icon, {bool isPercent = false}) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isPercent ? '${value.toStringAsFixed(1)}%' : money.format(value),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
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

  Widget _buildChart(List<Map<String, dynamic>> months) {
    return SizedBox(
      height: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
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
              lineBarsData: [
                LineChartBarData(
                  color: Colors.green,
                  spots: months.asMap().entries.map((e) {
                    return FlSpot(e.key + 1, (e.value['income_paid'] as num? ?? 0).toDouble());
                  }).toList(),
                  isCurved: false,
                  dotData: const FlDotData(show: true),
                ),
                LineChartBarData(
                  color: Colors.red,
                  spots: months.asMap().entries.map((e) {
                    return FlSpot(e.key + 1, (e.value['expense_paid'] as num? ?? 0).toDouble());
                  }).toList(),
                  isCurved: false,
                  dotData: const FlDotData(show: true),
                ),
                LineChartBarData(
                  color: Colors.blue,
                  spots: months.asMap().entries.map((e) {
                    return FlSpot(e.key + 1, (e.value['accumulated'] as num? ?? 0).toDouble());
                  }).toList(),
                  isCurved: false,
                  dotData: const FlDotData(show: true),
                ),
              ],
              lineTouchData: const LineTouchData(enabled: true),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(String label, List<Map<String, dynamic>> months, String field, bool bold,
      {bool positive = false, bool negative = false, bool isPercent = false}) {
    double total = 0;
    return DataRow(cells: [
      DataCell(Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
      ...List.generate(12, (i) {
        final m = months.length > i ? months[i] : <String, dynamic>{};
        final raw = (m[field] as num? ?? 0).toDouble();
        total += isPercent ? 0 : raw;
        final v = isPercent ? raw : raw;
        Color? c;
        if (positive && v > 0) c = Colors.green;
        if (negative && v > 0) c = Colors.red;
        if (field == 'profit' || field == 'cash_need' || field == 'accumulated') {
          c = v >= 0 ? Colors.green : Colors.red;
        }
        return DataCell(Align(
          alignment: Alignment.centerRight,
          child: Text(
            isPercent ? '${v.toStringAsFixed(1)}%' : money.format(v),
            style: TextStyle(color: c, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ));
      }),
      DataCell(Align(
        alignment: Alignment.centerRight,
        child: Text(
          isPercent
              ? months.isNotEmpty ? '${((months.last[field] as num? ?? 0)).toStringAsFixed(1)}%' : ''
              : money.format(total),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      )),
    ]);
  }
}
