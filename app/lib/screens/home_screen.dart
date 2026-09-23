import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
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
  List<dynamic> recurring = [];
  bool loading = true;
  DateTime focusedDay = DateTime.now();
  DateTime selectedDay = DateTime.now();

  String get _month =>
      '${focusedDay.year}-${focusedDay.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final [accountsRes, transactionsRes, budgetsRes, recurringRes] =
          await Future.wait([
        ApiService.get('/accounts'),
        ApiService.get('/transactions?month=$_month&limit=500'),
        ApiService.get('/budgets?month=$_month'),
        ApiService.get('/recurring'),
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
        recurring = ApiService.decode(recurringRes) is List
            ? ApiService.decode(recurringRes) as List
            : [];
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  // Saldo total: poupança e contas de investimento ficam de fora
  // (aparecem na tela de Investimentos).
  double get totalBalance => accounts
      .where((a) => a.type != 'savings' && a.type != 'investment')
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

  // Marcadores do calendario: despesas nao pagas + faturas com vencimento.
  Map<DateTime, List<Map<String, dynamic>>> get _events {
    final map = <DateTime, List<Map<String, dynamic>>>{};
    void add(DateTime d, Map<String, dynamic> item) {
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(item);
    }

    for (final t in transactions) {
      if (t.isExpense && !t.isPaid && t.cardId == null) {
        add(t.date, {
          'label': t.description ?? t.categoryName ?? 'Despesa',
          'amount': t.amount,
          'kind': 'expense',
        });
      }
    }
    for (final inv in cardInvoices) {
      if (inv['due_date'] == null) continue;
      final d = DateTime.tryParse('${inv['due_date']}'.substring(0, 10));
      if (d == null) continue;
      add(d, {
        'label': 'Fatura ${inv['card_name'] ?? ''}',
        'amount': (inv['total_amount'] as num?)?.toDouble() ?? 0,
        'kind': 'invoice',
        'paid': inv['status'] == 'paid',
      });
    }
    for (final r in recurring) {
      if (r['type'] != 'expense') continue;
      for (final d in _occurrencesInMonth(r)) {
        add(d, {
          'label': r['description'] ?? r['category_name'] ?? 'Despesa recorrente',
          'amount': (r['amount'] as num?)?.toDouble() ?? 0,
          'kind': 'recurring',
        });
      }
    }
    return map;
  }

  // Dias do mes em foco em que uma recorrencia acontece.
  List<DateTime> _occurrencesInMonth(dynamic r) {
    final start = DateTime.tryParse('${r['start_date']}'.substring(0, 10));
    if (start == null) return [];
    final end = r['end_date'] != null
        ? DateTime.tryParse('${r['end_date']}'.substring(0, 10))
        : null;
    final year = focusedDay.year;
    final month = focusedDay.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final out = <DateTime>[];

    bool inRange(DateTime d) =>
        !d.isBefore(DateTime(start.year, start.month, start.day)) &&
        (end == null ||
            !d.isAfter(DateTime(end.year, end.month, end.day)));

    switch ('${r['frequency']}') {
      case 'monthly':
        final d = DateTime(
          year,
          month,
          start.day > daysInMonth ? daysInMonth : start.day,
        );
        if (inRange(d)) out.add(d);
      case 'weekly':
        var d = DateTime(year, month, 1);
        while (d.weekday != start.weekday && d.month == month) {
          d = d.add(const Duration(days: 1));
        }
        while (d.month == month) {
          if (inRange(d)) out.add(d);
          d = d.add(const Duration(days: 7));
        }
      case 'yearly':
        if (start.month == month) {
          final d = DateTime(
            year,
            month,
            start.day > daysInMonth ? daysInMonth : start.day,
          );
          if (inRange(d)) out.add(d);
        }
      case 'daily':
        for (var day = 1; day <= daysInMonth; day++) {
          final d = DateTime(year, month, day);
          if (inRange(d)) out.add(d);
        }
    }
    return out;
  }

  List<Map<String, dynamic>> _eventsFor(DateTime day) =>
      _events[DateTime(day.year, day.month, day.day)] ?? [];

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

  void _showDayDetails(DateTime day) {
    final items = _eventsFor(day);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fmtDate(day),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nada a pagar neste dia.'),
                )
              else
                ...items.map(
                  (e) => ListTile(
                    dense: true,
                    leading: Icon(
                      e['kind'] == 'invoice'
                          ? Icons.credit_card
                          : e['kind'] == 'recurring'
                              ? Icons.repeat
                              : Icons.receipt_long,
                      color: e['kind'] == 'invoice'
                          ? Colors.deepPurple
                          : e['kind'] == 'recurring'
                              ? Colors.orange.shade700
                              : Colors.red.shade600,
                    ),
                    title: Text('${e['label']}'),
                    subtitle: e['paid'] == true ? const Text('Paga') : null,
                    trailing: Text(
                      'R\$ ${fmtMoney((e['amount'] as double))}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthNames = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${monthNames[focusedDay.month]} ${focusedDay.year}'),
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        onPressed: _openAdd,
        child: const Icon(Icons.add),
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
                        _buildCalendar(),
                        const SizedBox(height: 16),
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
    );
  }

  Widget _buildCalendar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TableCalendar<dynamic>(
          firstDay: DateTime(2020),
          lastDay: DateTime(2035),
          focusedDay: focusedDay,
          selectedDayPredicate: (d) => isSameDay(d, selectedDay),
          locale: 'pt_BR',
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Mês'},
          headerStyle: const HeaderStyle(formatButtonVisible: false),
          eventLoader: _eventsFor,
          onDaySelected: (sel, foc) {
            setState(() {
              selectedDay = sel;
              focusedDay = foc;
            });
            _showDayDetails(sel);
          },
          onPageChanged: (foc) {
            if (foc.year == focusedDay.year && foc.month == focusedDay.month) {
              return;
            }
            setState(() {
              focusedDay = foc;
              loading = true;
            });
            _loadData();
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              final kinds = events.map((e) => (e as Map)['kind']).toSet();
              final colors = <Color>[
                if (kinds.contains('invoice')) Colors.deepPurple,
                if (kinds.contains('expense'))
                  Theme.of(context).colorScheme.error,
                if (kinds.contains('recurring')) Colors.orange.shade700,
              ];
              return Positioned(
                bottom: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < colors.length; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors[i],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            'Saldo total',
            totalBalance,
            scheme.primaryContainer,
            scheme.onPrimaryContainer,
            Icons.account_balance_wallet,
          ),
        ),
        const SizedBox(width: 8),
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
