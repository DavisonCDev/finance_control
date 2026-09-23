import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import '../utils/money_parser.dart';
import '../utils/formatters.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> accounts = [];
  bool loading = true;

  // Tipos oferecidos no cadastro (poupança não soma no saldo total:
  // aparece na tela de Investimentos).
  static const _types = {
    'checking': 'Conta corrente',
    'savings': 'Poupança',
    'cash': 'Carteira',
  };

  static IconData _iconFor(String type) => switch (type) {
        'checking' => Icons.account_balance,
        'savings' => Icons.savings,
        'cash' => Icons.account_balance_wallet,
        'investment' => Icons.trending_up,
        'digital' => Icons.phone_android,
        _ => Icons.wallet,
      };

  double get _totalBalance => accounts
      .where((a) => a.type != 'savings' && a.type != 'investment')
      .fold(0.0, (s, a) => s + a.currentBalance);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/accounts');
    setState(() {
      accounts = (ApiService.decode(res) as List)
          .map((e) => Account.fromJson(e))
          .toList();
      loading = false;
    });
  }

  Future<void> _openForm({Account? account}) async {
    final isEditing = account != null;
    final nameController = TextEditingController(
      text: isEditing ? account.name : '',
    );
    final balanceController = TextEditingController(
      text: fmtMoney((isEditing ? account.initialBalance : 0)),
    );
    String type = isEditing ? account.type : 'checking';
    if (!_types.containsKey(type)) type = 'checking';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar conta' : 'Nova conta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'Saldo inicial'),
            ),
            DropdownButtonFormField(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: _types.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Icon(_iconFor(e.key), size: 20),
                          const SizedBox(width: 8),
                          Text(e.value),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => type = v!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final initial = parseMoney(balanceController.text);
              if (initial == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saldo inicial inválido')),
                );
                return;
              }
              final body = {
                'name': nameController.text,
                'type': type,
                'initial_balance': initial,
              };
              if (isEditing) {
                await ApiService.put('/accounts/${account.id}', body);
              } else {
                await ApiService.post('/accounts', body);
              }
              if (mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Account a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar conta?'),
        content: Text(
          'Deseja remover a conta "${a.name}"? Se houver transações vinculadas, a conta não poderá ser excluída.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.delete('/accounts/${a.id}');
      if (res.statusCode == 200 || res.statusCode == 204) {
        _load();
      } else {
        final data = ApiService.decode(res) as Map<String, dynamic>;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Erro ao apagar conta')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    children: [
                      Card(
                        margin: const EdgeInsets.all(12),
                        child: ListTile(
                          leading: Icon(
                            Icons.account_balance_wallet,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: const Text('Saldo total'),
                          trailing: Text(
                            'R\$ ${fmtMoney(_totalBalance)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      ...accounts.map((a) {
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(_iconFor(a.type)),
                          ),
                          title: Text(a.name),
                          subtitle: Text(Account.typeLabel(a.type)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'R\$ ${fmtMoney(a.currentBalance)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openForm(account: a),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () => _delete(a),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'accounts_fab',
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
