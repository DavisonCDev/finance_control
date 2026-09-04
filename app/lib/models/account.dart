class Account {
  final int id;
  final String name;
  final String type;
  final double initialBalance;
  final double currentBalance;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.currentBalance,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      initialBalance: double.tryParse(json['initial_balance'].toString()) ?? 0.0,
      currentBalance: double.tryParse(json['current_balance'].toString()) ?? 0.0,
    );
  }

  static String typeLabel(String type) {
    switch (type) {
      case 'checking':
        return 'Conta corrente';
      case 'savings':
        return 'Poupança';
      case 'digital':
        return 'Conta digital';
      case 'cash':
        return 'Dinheiro';
      case 'investment':
        return 'Investimento';
      case 'salary':
        return 'Conta salário';
      default:
        return 'Outro';
    }
  }
}
