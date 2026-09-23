import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/category.dart';
import '../models/card.dart' as models;
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../utils/icon_map.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

class NewTransactionScreen extends StatefulWidget {
  final Transaction? transactionToEdit;
  final String? initialType;
  const NewTransactionScreen({super.key, this.transactionToEdit, this.initialType});

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  List<Account> accounts = [];
  List<Category> categories = [];
  Map<int, Category> _catById = {};

  // Selecao em dois niveis: categoria (pai) e, se houver, subcategoria.
  List<Category> get _parents {
    final list = categories.where((c) => c.parentId == null).toList();
    list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return list;
  }

  List<Category> _subsOf(int parentId) {
    final list =
        categories.where((c) => c.parentId == parentId).toList();
    list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return list;
  }

  // Categoria efetiva salva: a subcategoria quando escolhida.
  int? get selectedCategoryId => selectedSubId ?? selectedParentId;
  List<models.CardModel> cards = [];
  String type = 'expense';
  int? selectedAccountId;
  int? selectedTransferAccountId;
  int? selectedParentId;
  int? selectedSubId;
  int? _initialCategoryId;
  int? selectedCardId;
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  final installmentsController = TextEditingController(text: '1');
  DateTime date = DateTime.now();
  bool isRecurring = false;
  String frequency = 'monthly';
  DateTime? endDate;
  bool payWithCard = false;
  bool payInstallments = false;
  bool isPaid = true;
  bool loading = true;
  bool saving = false;

  bool get isEditing => widget.transactionToEdit != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transactionToEdit;
    type = widget.initialType ?? t?.type ?? 'expense';
    if (t != null) {
      selectedAccountId = t.accountId;
      selectedTransferAccountId = t.transferAccountId;
      _initialCategoryId = t.categoryId;
      selectedCardId = t.cardId;
      payWithCard = t.cardId != null;
      payInstallments = (t.installmentId != null);
      amountController.text = fmtMoney(t.amount);
      descriptionController.text = t.description ?? '';
      date = t.date;
      isPaid = t.isPaid;
    }
    _load();
  }

  Future<void> _load() async {
    final [aRes, cardRes] = await Future.wait([
      ApiService.get('/accounts'),
      ApiService.get('/cards'),
    ]);
    List<Category> loadedCategories = [];
    if (type != 'transfer') {
      final cRes = await ApiService.get('/categories?type=$type&flat=true');
      loadedCategories = (ApiService.decode(cRes) as List)
          .map((e) => Category.fromJson(e))
          .toList();
      _catById = {for (final c in loadedCategories) c.id: c};
      // Ao editar: se a categoria salva e subcategoria, preenche pai + filho.
      if (_initialCategoryId != null) {
        final cat = _catById[_initialCategoryId];
        if (cat != null && cat.parentId != null) {
          selectedParentId = cat.parentId;
          selectedSubId = cat.id;
        } else {
          selectedParentId = cat?.id ?? _initialCategoryId;
        }
      }
    }
    setState(() {
      accounts = (ApiService.decode(aRes) as List)
          .map((e) => Account.fromJson(e))
          .toList();
      cards = (ApiService.decode(cardRes) as List)
          .map((e) => models.CardModel.fromJson(e))
          .toList();
      categories = loadedCategories;
      if (accounts.isNotEmpty && selectedAccountId == null) {
        selectedAccountId = accounts.first.id;
      }
      if (type == 'transfer' &&
          accounts.length > 1 &&
          selectedTransferAccountId == null) {
        selectedTransferAccountId =
            accounts.firstWhere((a) => a.id != selectedAccountId,
                orElse: () => accounts.first).id;
      }
      loading = false;
    });
  }

  String get _title => switch (type) {
        'income' => isEditing ? 'Editar receita' : 'Nova receita',
        'transfer' => isEditing ? 'Editar transferência' : 'Nova transferência',
        _ => isEditing ? 'Editar despesa' : 'Nova despesa',
      };

  Future<void> _save() async {
    final amount = parseMoney(amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido.')),
      );
      return;
    }
    if (selectedCardId == null && selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma conta.')),
      );
      return;
    }
    if (type == 'transfer' &&
        selectedTransferAccountId == selectedAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Origem e destino devem ser diferentes.')),
      );
      return;
    }

    setState(() => saving = true);
    final dateStr = date.toIso8601String().split('T').first;

    http.Response res;
    if (isEditing) {
      final body = <String, dynamic>{
        'type': type,
        'amount': amount,
        'date': dateStr,
        'description': descriptionController.text,
        'category_id': selectedCategoryId,
        'is_paid': isPaid,
      };
      if (selectedCardId != null) {
        body['card_id'] = selectedCardId;
      } else {
        body['account_id'] = selectedAccountId;
        if (type == 'transfer') {
          body['transfer_account_id'] = selectedTransferAccountId;
        }
      }
      res = await ApiService.put(
          '/transactions/${widget.transactionToEdit!.id}', body);
    } else if (isRecurring && type != 'transfer') {
      // Despesa/receita recorrente: o backend gera as transacoes e a previsao.
      res = await ApiService.post('/recurring', {
        'account_id': selectedAccountId,
        'category_id': selectedCategoryId,
        'type': type,
        'amount': amount,
        'description': descriptionController.text,
        'frequency': frequency,
        'start_date': dateStr,
        if (endDate != null)
          'end_date': endDate!.toIso8601String().split('T').first,
      });
    } else if (selectedCardId != null && type == 'expense') {
      res = await ApiService.post('/cards/$selectedCardId/purchases', {
        'amount': amount,
        'date': dateStr,
        'category_id': selectedCategoryId,
        'description': descriptionController.text,
        'installments':
            payInstallments ? (int.tryParse(installmentsController.text) ?? 1) : 1,
      });
    } else {
      res = await ApiService.post('/transactions', {
        'type': type,
        'account_id': selectedAccountId,
        if (type == 'transfer')
          'transfer_account_id': selectedTransferAccountId,
        'category_id': selectedCategoryId,
        'amount': amount,
        'date': dateStr,
        'description': descriptionController.text,
        'is_paid': isPaid,
      });
    }

    if (!mounted) return;
    setState(() => saving = false);
    if (res.statusCode == 200 || res.statusCode == 201) {
      Navigator.pop(context, true);
    } else {
      final data = ApiService.decode(res);
      final msg = data is Map ? (data['error'] ?? data['message'] ?? 'Erro') : 'Erro ao salvar';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$msg')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir transação?'),
        content: const Text('O saldo e as previsões serão atualizados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await ApiService.delete(
        '/transactions/${widget.transactionToEdit!.id}');
    if (!mounted) return;
    if (res.statusCode == 200) {
      Navigator.pop(context, true);
    } else {
      final data = ApiService.decode(res);
      final msg = data is Map ? (data['error'] ?? 'Erro ao excluir') : 'Erro ao excluir';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (isEditing)
            IconButton(
              icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        hintText: 'Ex.: Mercado, salário, aluguel',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        prefixText: 'R\$ ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (type != 'transfer') ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey('parent_$type'),
                        initialValue: selectedParentId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: _parents
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      iconFromName(c.icon),
                                      color: c.getColor(),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        c.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          selectedParentId = v;
                          selectedSubId = null;
                        }),
                      ),
                      if (selectedParentId != null &&
                          _subsOf(selectedParentId!).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          key: ValueKey('sub_$selectedParentId'),
                          initialValue: selectedSubId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Subcategoria',
                            hintText: 'Opcional',
                          ),
                          items: _subsOf(selectedParentId!)
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Row(
                                    children: [
                                      Icon(
                                        iconFromName(c.icon),
                                        color: c.getColor(),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          c.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => selectedSubId = v),
                        ),
                      ],
                    ],
                    if (type != 'transfer') const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Data'),
                      subtitle: Text(fmtDate(date)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setState(() {
                            date = picked;
                            // Data futura => ainda a pagar; hoje/passado => pago.
                            final today = DateTime.now();
                            final todayOnly = DateTime(
                              today.year, today.month, today.day,
                            );
                            isPaid = !DateTime(
                              picked.year, picked.month, picked.day,
                            ).isAfter(todayOnly);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    if (selectedCardId == null)
                      DropdownButtonFormField<int>(
                        initialValue: selectedAccountId,
                        decoration: InputDecoration(
                          labelText: type == 'transfer'
                              ? 'Conta de origem'
                              : 'Conta',
                        ),
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(a.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => selectedAccountId = v),
                      ),
                    if (type == 'transfer')
                      DropdownButtonFormField<int>(
                        initialValue: selectedTransferAccountId,
                        decoration: const InputDecoration(
                          labelText: 'Conta de destino',
                        ),
                        items: accounts
                            .where((a) => a.id != selectedAccountId)
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(a.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => selectedTransferAccountId = v),
                      ),
                    if (type == 'expense' && cards.isNotEmpty) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Débito / conta'),
                            icon: Icon(Icons.account_balance),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Cartão de crédito'),
                            icon: Icon(Icons.credit_card),
                          ),
                        ],
                        selected: {payWithCard},
                        onSelectionChanged: (s) => setState(() {
                          payWithCard = s.first;
                          selectedCardId =
                              payWithCard ? (selectedCardId ?? cards.first.id) : null;
                        }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (payWithCard) ...[
                      DropdownButtonFormField<int>(
                        initialValue: selectedCardId,
                        decoration:
                            const InputDecoration(labelText: 'Cartão'),
                        items: cards
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => selectedCardId = v),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('À vista'),
                            icon: Icon(Icons.payments_outlined),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Parcelado'),
                            icon: Icon(Icons.view_week_outlined),
                          ),
                        ],
                        selected: {payInstallments},
                        onSelectionChanged: (s) =>
                            setState(() => payInstallments = s.first),
                      ),
                      if (payInstallments) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: installmentsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Número de parcelas',
                          ),
                        ),
                      ],
                    ],
                    if (type != 'transfer' && !payWithCard && !isRecurring)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pago'),
                        subtitle: isPaid
                            ? null
                            : const Text('Fica pendente até você confirmar'),
                        value: isPaid,
                        onChanged: (v) => setState(() => isPaid = v),
                      ),
                    if (type != 'transfer' && !isEditing && selectedCardId == null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Repetir (recorrente)'),
                        subtitle: isRecurring
                            ? const Text('Gera lançamentos e previsões futuras')
                            : null,
                        value: isRecurring,
                        onChanged: (v) => setState(() => isRecurring = v),
                      ),
                    if (isRecurring && type != 'transfer' && !isEditing) ...[
                      DropdownButtonFormField<String>(
                        initialValue: frequency,
                        decoration:
                            const InputDecoration(labelText: 'Frequência'),
                        items: const [
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('Mensal (todo dia igual à data)'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Semanal (mesmo dia da semana)'),
                          ),
                          DropdownMenuItem(
                            value: 'yearly',
                            child: Text('Anual'),
                          ),
                        ],
                        onChanged: (v) => setState(() => frequency = v!),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Repetir até (opcional)'),
                        subtitle: Text(
                          endDate == null
                              ? 'Sem data final'
                              : fmtDate(endDate!),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate ?? date,
                            firstDate: date,
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setState(() => endDate = picked);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: saving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(saving ? 'Salvando...' : 'Salvar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
