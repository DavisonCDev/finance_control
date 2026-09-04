import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/api_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _format = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<dynamic> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _load(_focusedDay);
  }

  Future<void> _load(DateTime day) async {
    final month = day.toIso8601String().substring(0, 7);
    final res = await ApiService.get('/calendar?month=$month');
    setState(() {
      events = ApiService.decode(res) as List;
      loading = false;
    });
  }

  List<dynamic> _eventsForDay(DateTime day) {
    final dayStr = day.toIso8601String().split('T').first;
    return events.where((e) => e['event_date'].toString().startsWith(dayStr)).toList();
  }

  Future<void> _addEvent() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String type = 'bill';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo evento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor')),
            DropdownButtonFormField(
              value: type,
              items: const [
                DropdownMenuItem(value: 'bill', child: Text('Conta')),
                DropdownMenuItem(value: 'salary', child: Text('Salário')),
                DropdownMenuItem(value: 'invoice', child: Text('Fatura')),
                DropdownMenuItem(value: 'installment', child: Text('Parcela')),
              ],
              onChanged: (v) => type = v!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final day = _selectedDay ?? _focusedDay;
              await ApiService.post('/calendar', {
                'title': titleController.text,
                'type': type,
                'event_date': day.toIso8601String().split('T').first,
                'amount': double.tryParse(amountController.text) ?? 0,
              });
              if (mounted) Navigator.pop(context);
              _load(day);
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
      appBar: AppBar(title: const Text('Calendário financeiro')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay: DateTime(2030),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                  calendarFormat: _format,
                  onFormatChanged: (f) => setState(() => _format = f),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                    _load(selected);
                  },
                  onPageChanged: (d) => _load(d),
                  eventLoader: _eventsForDay,
                ),
                Expanded(
                  child: ListView(
                    children: _eventsForDay(_selectedDay ?? _focusedDay)
                        .map((e) => ListTile(
                              leading: Icon(
                                e['paid'] == 1 ? Icons.check_circle : Icons.circle,
                                color: e['paid'] == 1 ? Colors.green : Colors.orange,
                              ),
                              title: Text(e['title']),
                              subtitle: Text('R\$ ${(double.tryParse(e['amount'].toString()) ?? 0).toStringAsFixed(2)}'),
                              trailing: Text(e['type'].toString().toUpperCase()),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_fab',
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
