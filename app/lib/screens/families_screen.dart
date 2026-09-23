import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FamiliesScreen extends StatefulWidget {
  const FamiliesScreen({super.key});

  @override
  State<FamiliesScreen> createState() => _FamiliesScreenState();
}

class _FamiliesScreenState extends State<FamiliesScreen> {
  List<dynamic> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/families');
    setState(() {
      items = ApiService.decode(res) as List;
      loading = false;
    });
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova família'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await ApiService.post('/families', {'name': nameController.text});
              if (mounted) Navigator.pop(context);
              _load();
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
      appBar: AppBar(
        title: const Text('Família'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final f = items[i];
                return ListTile(
                  leading: const Icon(Icons.people),
                  title: Text(f['name']),
                  subtitle: Text(f['role'] ?? 'membro'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'families_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
