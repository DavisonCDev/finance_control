import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/notifications');
    setState(() {
      final data = ApiService.decode(res) as Map<String, dynamic>;
      items = data['notifications'] as List? ?? [];
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final n = items[i];
                return ListTile(
                  leading: const Icon(Icons.notifications),
                  title: Text(n['title']),
                  subtitle: Text(n['message'] ?? ''),
                  trailing: n['read_at'] != null
                      ? Icon(Icons.check, color: Colors.green.shade600)
                      : null,
                );
              },
            ),
    );
  }
}
