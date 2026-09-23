import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'cashflow_yearly_screen.dart';
import 'dre_detailed_screen.dart';
import 'dre_screen.dart';
import 'goals_monthly_screen.dart';
import '../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> report = {};
  bool loading = true;
  String? error;
  final month = DateTime.now().toIso8601String().substring(0, 7);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.get('/reports/monthly?month=$month');
      setState(() {
        report = ApiService.decode(res) as Map<String, dynamic>;
        error = null;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error =
            'Não foi possível carregar os relatórios. Verifique a conexão com a API.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = (report['categories'] as List? ?? []);
    final income = (report['total_income'] as num? ?? 0).toDouble();
    final expense = (report['total_expense'] as num? ?? 0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo de $month',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Relatórios anuais',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _reportChip(
                            context,
                            'Metas mensais',
                            Icons.calendar_month,
                            const GoalsMonthlyScreen(),
                          ),
                          _reportChip(
                            context,
                            'Fluxo de caixa',
                            Icons.timeline,
                            const CashflowYearlyScreen(),
                          ),
                          _reportChip(
                            context,
                            'Resultado do ano',
                            Icons.assessment_outlined,
                            const DREScreen(),
                          ),
                          _reportChip(
                            context,
                            'Resultado por grupo',
                            Icons.view_list,
                            const DREDetailedScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (error != null) ...[
                        Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _buildCard(
                              'Receitas',
                              income,
                              Theme.of(context).colorScheme.tertiaryContainer,
                              Theme.of(context).colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCard(
                              'Despesas',
                              expense,
                              Theme.of(context).colorScheme.errorContainer,
                              Theme.of(context).colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (categories.isNotEmpty) ...[
                        Text(
                          'Gastos por categoria',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 220,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: categories.map((c) {
                                final color = c['category_color'] ?? '#000000';
                                final hex = color.toString().replaceAll(
                                  '#',
                                  '',
                                );
                                return PieChartSectionData(
                                  color: Color(int.parse('FF$hex', radix: 16)),
                                  value: (c['spent'] as num).toDouble(),
                                  title:
                                      '${(double.tryParse(c['percent'].toString()) ?? 0).toStringAsFixed(0)}%',
                                  radius: 60,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Orçamento vs gasto',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        ...categories.map((c) {
                          final percent =
                              double.tryParse(c['percent'].toString()) ?? 0;
                          final isOver = percent > 100;
                          return ListTile(
                            leading: Icon(
                              Icons.circle,
                              color: Color(
                                int.parse(
                                  'FF${c['category_color'].toString().replaceAll('#', '')}',
                                  radix: 16,
                                ),
                              ),
                            ),
                            title: Text(c['category_name']),
                            subtitle: LinearProgressIndicator(
                              value: percent / 100,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              color: isOver
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            trailing: Text(
                              'R\$ ${(c['spent'] as num).toStringAsFixed(0)} / ${(c['budgeted'] as num).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }),
                      ] else
                        const Text(
                          'Nenhum orçamento para este mês. Cadastre um orçamento primeiro.',
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _reportChip(
    BuildContext context,
    String label,
    IconData icon,
    Widget screen,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );
      },
    );
  }

  Widget _buildCard(String label, double value, Color bg, Color fg) {
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: fg.withValues(alpha: 0.7))),
            const SizedBox(height: 8),
            Text(
              'R\$ ${fmtMoney(value)}',
              style: TextStyle(
                color: fg,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
