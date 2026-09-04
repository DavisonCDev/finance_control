import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/category.dart';
import '../services/api_service.dart';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  List<Account> accounts = [];
  List<Category> categories = [];
  List<Map<String, dynamic>> parsedTransactions = [];
  int? selectedAccountId;
  int? selectedCategoryId;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final [aRes, cRes] = await Future.wait([
      ApiService.get('/accounts'),
      ApiService.get('/categories'),
    ]);
    setState(() {
      accounts = (ApiService.decode(aRes) as List).map((e) => Account.fromJson(e)).toList();
      categories = (ApiService.decode(cRes) as List).map((e) => Category.fromJson(e)).toList();
      if (accounts.isNotEmpty) selectedAccountId = accounts.first.id;
      if (categories.isNotEmpty) selectedCategoryId = categories.first.id;
    });
  }

  String _categoryName(int? id) {
    if (id == null) return 'Padrão';
    final c = categories.firstWhere((c) => c.id == id, orElse: () => Category(id: 0, name: 'Desconhecida', type: 'expense', color: '#000000', icon: ''));
    return c.name;
  }

  Future<void> _pickAndUploadPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => loading = true);

    final bytes = await file.readAsBytes();
    final token = await ApiService.getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/import-pdf/'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.name,
    ));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final data = jsonDecode(body);

    setState(() {
      parsedTransactions = (data['transactions'] as List? ?? [])
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();
      for (var t in parsedTransactions) {
        t['category_id'] = t['suggested_category_id'] ?? selectedCategoryId;
      }
      loading = false;
    });

    if (parsedTransactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma transação encontrada no PDF. Verifique se o formato é do Itaú.')),
        );
      }
    }
  }

  Future<void> _importPdfTransactions() async {
    if (selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma conta')));
      return;
    }

    final res = await ApiService.post('/import-pdf/import', {
      'account_id': selectedAccountId,
      'category_id': selectedCategoryId,
      'transactions': parsedTransactions,
    });

    if (res.statusCode == 200) {
      setState(() => parsedTransactions = []);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transações importadas com sucesso!')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${res.body}')));
    }
  }

  Future<void> _export() async {
    final res = await ApiService.get('/import-export/export');
    if (res.statusCode == 200) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Exportação CSV'),
            content: SingleChildScrollView(child: Text(res.body)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _editTransaction(int index) async {
    final t = parsedTransactions[index];
    String type = t['type'] as String;
    int? categoryId = t['category_id'] as int?;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editar transação'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Despesa')),
                  ButtonSegment(value: 'income', label: Text('Receita')),
                ],
                selected: {type},
                onSelectionChanged: (s) {
                  setDialogState(() {
                    type = s.first;
                    categoryId = categories.firstWhere((c) => c.type == type).id;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: categories
                    .where((c) => c.type == type)
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setDialogState(() => categoryId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                setState(() {
                  final updated = Map<String, dynamic>.from(parsedTransactions[index]);
                  updated['type'] = type;
                  updated['category_id'] = categoryId;
                  parsedTransactions[index] = updated;
                });
                Navigator.pop(ctx);
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
      appBar: AppBar(title: const Text('Importar / Exportar')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.download),
                    label: const Text('Exportar transações (CSV)'),
                  ),
                  const SizedBox(height: 24),
                  Text('Importar por PDF (Itaú)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedAccountId,
                      decoration: const InputDecoration(labelText: 'Conta destino'),
                      items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                      onChanged: (v) => setState(() => selectedAccountId = v),
                    ),
                  const SizedBox(height: 8),
                  if (categories.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedCategoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoria padrão'),
                      items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => selectedCategoryId = v),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _pickAndUploadPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Selecionar PDF do extrato'),
                  ),
                  if (parsedTransactions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('${parsedTransactions.length} transações encontradas:', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...parsedTransactions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final t = entry.value;
                      return ListTile(
                        title: Text(t['description'] ?? ''),
                        subtitle: Text('${t['date']} • R\$ ${t['amount'].toStringAsFixed(2)} • ${t['type'] == 'income' ? 'Receita' : 'Despesa'}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: t['type'] == 'income' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _categoryName(t['category_id']),
                            style: TextStyle(
                              color: t['type'] == 'income' ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () => _editTransaction(i),
                      );
                    }),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _importPdfTransactions,
                      child: const Text('Confirmar importação'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
