import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InstallmentsScreen extends StatefulWidget {
  const InstallmentsScreen({super.key});

  @override
  State<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends State<InstallmentsScreen> {
  List<dynamic> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.get('/installments');
      setState(() {
        items = ApiService.decode(res) as List;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parcelamentos'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Nenhum parcelamento cadastrado.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return ListTile(
                      title: Text(item['description'] ?? 'Parcelamento'),
                      subtitle: Text(
                        'Parcela ${item['current_installment']}/${item['total_installments']}',
                      ),
                      trailing: Text('R\$ ${item['amount']}'),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
