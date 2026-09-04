import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> report = {};
  bool loading = true;
  final month = DateTime.now().toIso8601String().substring(0, 7);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/reports/monthly?month=$month');
    setState(() {
      report = ApiService.decode(res) as Map<String, dynamic>;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = (report['categories'] as List? ?? []);
    final income = (report['total_income'] as num? ?? 0).toDouble();
    final expense = (report['total_expense'] as num? ?? 0).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumo de $month',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildCard('Receitas', income, Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildCard('Despesas', expense, Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (categories.isNotEmpty) ...[
                    Text('Gastos por categoria', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: categories.map((c) {
                            final color = c['category_color'] ?? '#000000';
                            final hex = color.toString().replaceAll('#', '');
                            return PieChartSectionData(
                              color: Color(int.parse('FF$hex', radix: 16)),
                              value: (c['spent'] as num).toDouble(),
                              title: '${(double.tryParse(c['percent'].toString()) ?? 0).toStringAsFixed(0)}%',
                              radius: 60,
                              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Orçamento vs gasto', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    ...categories.map((c) {
                      final percent = double.tryParse(c['percent'].toString()) ?? 0;
                      final isOver = percent > 100;
                      return ListTile(
                        leading: Icon(Icons.circle, color: Color(int.parse('FF${c['category_color'].toString().replaceAll('#', '')}', radix: 16))),
                        title: Text(c['category_name']),
                        subtitle: LinearProgressIndicator(
                          value: percent / 100,
                          backgroundColor: Colors.grey.shade300,
                          color: isOver ? Colors.red : Colors.blue,
                        ),
                        trailing: Text(
                          'R\$ ${(c['spent'] as num).toStringAsFixed(0)} / ${(c['budgeted'] as num).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ] else
                    const Text('Nenhum orçamento para este mês. Cadastre um orçamento primeiro.'),
                ],
              ),
            ),
    );
  }

  Widget _buildCard(String label, double value, Color color) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              'R\$ ${value.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
