import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import 'new_transaction_screen.dart';
import 'login_screen.dart';
import '../utils/formatters.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Account> accounts = [];
  List<Transaction> transactions = [];
  List<dynamic> cardInvoices = [];
  bool loading = true;
  DateTime focusedDay = DateTime.now();

  String get _month =>
      '${focusedDay.year}-${focusedDay.month.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() {
      focusedDay = DateTime(focusedDay.year, focusedDay.month + delta);
      loading = true;
    });
    _loadData();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final [accountsRes, transactionsRes, budgetsRes] = await Future.wait([
        ApiService.get('/accounts'),
        ApiService.get('/transactions?month=$_month&limit=500'),
        ApiService.get('/budgets?month=$_month'),
      ]);

      if (accountsRes.statusCode == 401) {
        await ApiService.removeToken();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
        return;
      }

      setState(() {
        accounts = (ApiService.decode(accountsRes) as List)
            .map((e) => Account.fromJson(e))
            .toList();
        final tData =
            ApiService.decode(transactionsRes) as Map<String, dynamic>;
        transactions = (tData['transactions'] as List? ?? [])
            .map((e) => Transaction.fromJson(e))
            .toList();
        final bData = ApiService.decode(budgetsRes) as Map<String, dynamic>;
        cardInvoices = bData['card_invoices'] as List? ?? [];
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  // Saldo em contas: poupança e investimentos ficam de fora (tela de
  // Investimentos) e carteira/dinheiro aparece separada no card próprio.
  double get totalBalance => accounts
      .where((a) => a.type != 'savings' && a.type != 'investment' && a.type != 'cash')
      .fold(0.0, (sum, a) => sum + a.currentBalance);

  // Dinheiro em carteira (tipo cash): exibido separado do saldo em contas.
  double get walletBalance => accounts
      .where((a) => a.type == 'cash')
      .fold(0.0, (sum, a) => sum + a.currentBalance);

  double get monthlyExpensePaid => transactions
      .where((t) => t.isExpense && t.cardId == null && t.isPaid)
      .fold(0.0, (sum, t) => sum + t.amount);

  // Total de cartão no mês: soma das faturas que VENCEM no mês
  // (não pela data da compra).
  double get cardUsedMonth => cardInvoices.fold(
        0.0,
        (sum, i) => sum + ((i['total_amount'] as num?)?.toDouble() ?? 0),
      );

  // Despesas pagas por dia do mes (para o grafico).
  Map<int, double> get _dailyExpenses {
    final map = <int, double>{};
    for (final t in transactions) {
      if (t.isExpense && t.isPaid && t.cardId == null) {
        map[t.date.day] = (map[t.date.day] ?? 0) + t.amount;
      }
    }
    return map;
  }

  Future<void> _openAdd() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.arrow_downward, color: Colors.red.shade600),
              title: const Text('Despesa'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            ListTile(
              leading: Icon(Icons.arrow_upward, color: Colors.green.shade600),
              title: const Text('Receita'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.orange),
              title: const Text('Transferência'),
              onTap: () => Navigator.pop(context, 'transfer'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final changed = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewTransactionScreen(initialType: type)),
    );
    if (changed == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final monthNames = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
            ),
            Text('${monthNames[focusedDay.month]} ${focusedDay.year}'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            await ApiService.removeToken();
            if (context.mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          }),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 16),
                        _buildAccountsCard(),
                        const SizedBox(height: 16),
                        _buildChart(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        onPressed: _openAdd,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                'Saldo em contas',
                totalBalance,
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                Icons.account_balance,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summaryCard(
                'Carteira',
                walletBalance,
                scheme.tertiaryContainer,
                scheme.onTertiaryContainer,
                Icons.wallet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                'Despesas pagas',
                monthlyExpensePaid,
                scheme.errorContainer,
                scheme.onErrorContainer,
                Icons.payments,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summaryCard(
                'Cartão no mês',
                cardUsedMonth,
                const Color(0xFFD1C4E9),
                const Color(0xFF311B92),
                Icons.credit_card,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(
    String label,
    double value,
    Color bg,
    Color fg,
    IconData icon,
  ) {
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'R\$ ${fmtMoney(value)}',
                style: TextStyle(
                  color: fg,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Saldo atualizado de cada conta (poupanca/investimento ficam na
  // tela de Investimentos).
  Widget _buildAccountsCard() {
    IconData iconFor(String type) => switch (type) {
          'checking' => Icons.account_balance,
          'cash' => Icons.account_balance_wallet,
          'savings' => Icons.savings,
          'investment' => Icons.trending_up,
          _ => Icons.wallet,
        };
    final listed = accounts
        .where((a) => a.type != 'savings' && a.type != 'investment')
        .toList();
    if (listed.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            ...listed.map(
              (a) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(iconFor(a.type)),
                title: Text(a.name),
                subtitle: Text(Account.typeLabel(a.type)),
                trailing: Text(
                  'R\$ ${fmtMoney(a.currentBalance)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: a.currentBalance < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final daily = _dailyExpenses;
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
    final maxY = daily.values.fold(0.0, (a, b) => a > b ? a : b);
    final now = DateTime.now();
    final isCurrentMonth =
        focusedDay.year == now.year && focusedDay.month == now.month;
    // No mobile nao cabem 31 rotulos: mostra marcos a cada 5 dias
    // (+ ultimo dia) e o resto se explora pelo toque na barra.
    final labeled = {1, 5, 10, 15, 20, 25, daysInMonth};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Despesas por dia',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              'Toque em uma barra para ver o valor',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: daily.isEmpty
                  ? const Center(child: Text('Nenhuma despesa paga neste mês.'))
                  : BarChart(
                      BarChartData(
                        maxY: maxY * 1.2,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval:
                              maxY > 0 ? maxY / 3 : 1,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: scheme.outlineVariant
                                .withValues(alpha: 0.4),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (v, meta) {
                                final d = v.toInt();
                                if (!labeled.contains(d) ||
                                    d < 1 ||
                                    d > daysInMonth) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    '$d',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.outline,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, gi, rod, ri) {
                              if (rod.toY == 0) return null;
                              return BarTooltipItem(
                                'Dia ${group.x}\nR\$ ${fmtMoney(rod.toY)}',
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        barGroups: [
                          for (var d = 1; d <= daysInMonth; d++)
                            BarChartGroupData(
                              x: d,
                              barRods: [
                                BarChartRodData(
                                  toY: daily[d] ?? 0,
                                  width: 7,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: isCurrentMonth && d == now.day
                                        ? [
                                            scheme.tertiary,
                                            scheme.tertiary
                                                .withValues(alpha: 0.6),
                                          ]
                                        : [
                                            scheme.primary,
                                            scheme.primary
                                                .withValues(alpha: 0.55),
                                          ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
