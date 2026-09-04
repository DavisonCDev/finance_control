class Transaction {
  final int id;
  final int? accountId;
  final int? categoryId;
  final String type;
  final double amount;
  final DateTime date;
  final String? description;
  final String? categoryName;
  final String? categoryColor;
  final String? accountName;

  Transaction({
    required this.id,
    this.accountId,
    this.categoryId,
    required this.type,
    required this.amount,
    required this.date,
    this.description,
    this.categoryName,
    this.categoryColor,
    this.accountName,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      accountId: json['account_id'],
      categoryId: json['category_id'],
      type: json['type'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      date: DateTime.parse(json['date']),
      description: json['description'],
      categoryName: json['category_name'],
      categoryColor: json['category_color'],
      accountName: json['account_name'],
    );
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
}
