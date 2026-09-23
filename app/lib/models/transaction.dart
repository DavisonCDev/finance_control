class Transaction {
  final int id;
  final int? accountId;
  final int? categoryId;
  final int? cardId;
  final int? installmentId;
  final int? transferAccountId;
  final int? costCenterId;
  final int? contactId;
  final String type;
  final double amount;
  final DateTime date;
  final DateTime? accrualDate;
  final DateTime? paymentDate;
  final bool isPaid;
  final String paymentMethod;
  final String? description;
  final String? source;
  final String? classification;
  final String? pcReference;
  final String? item;
  final String? categoryName;
  final String? categoryParentName;
  final String? categoryColor;
  final String? categoryIcon;
  final String? accountName;
  final String? cardName;
  final String? transferAccountName;
  final String? costCenterName;
  final String? contactName;

  Transaction({
    required this.id,
    this.accountId,
    this.categoryId,
    this.cardId,
    this.installmentId,
    this.transferAccountId,
    this.costCenterId,
    this.contactId,
    required this.type,
    required this.amount,
    required this.date,
    this.accrualDate,
    this.paymentDate,
    this.isPaid = true,
    this.paymentMethod = 'OTHER',
    this.description,
    this.source,
    this.classification,
    this.pcReference,
    this.item,
    this.categoryName,
    this.categoryParentName,
    this.categoryColor,
    this.categoryIcon,
    this.accountName,
    this.cardName,
    this.transferAccountName,
    this.costCenterName,
    this.contactName,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      accountId: json['account_id'],
      categoryId: json['category_id'],
      cardId: json['card_id'],
      installmentId: json['installment_id'],
      transferAccountId: json['transfer_account_id'],
      costCenterId: json['cost_center_id'],
      contactId: json['contact_id'],
      type: json['type'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      date: DateTime.parse(json['date']),
      accrualDate: json['accrual_date'] != null
          ? DateTime.parse(json['accrual_date'])
          : null,
      paymentDate: json['payment_date'] != null
          ? DateTime.parse(json['payment_date'])
          : null,
      isPaid: json['is_paid'] == 1 || json['is_paid'] == true,
      paymentMethod: json['payment_method'] ?? 'OTHER',
      description: json['description'],
      source: json['source'],
      classification: json['classification'],
      pcReference: json['pc_reference'],
      item: json['item'],
      categoryName: json['category_name'],
      categoryParentName: json['category_parent_name'],
      categoryColor: json['category_color'],
      categoryIcon: json['category_icon'],
      accountName: json['account_name'],
      cardName: json['card_name'],
      transferAccountName: json['transfer_account_name'],
      costCenterName: json['cost_center_name'],
      contactName: json['contact_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'card_id': cardId,
      'installment_id': installmentId,
      'transfer_account_id': transferAccountId,
      'cost_center_id': costCenterId,
      'contact_id': contactId,
      'type': type,
      'amount': amount,
      'date': date.toIso8601String().substring(0, 10),
      'accrual_date': accrualDate?.toIso8601String().substring(0, 10),
      'payment_date': paymentDate?.toIso8601String().substring(0, 10),
      'is_paid': isPaid,
      'payment_method': paymentMethod,
      'description': description,
      'classification': classification,
      'pc_reference': pcReference,
      'item': item,
    };
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isTransfer => type == 'transfer';

  // "Pai › Filho" quando a categoria e uma subcategoria.
  String? get categoryLabel {
    if (categoryName == null) return null;
    return categoryParentName != null
        ? '$categoryParentName › $categoryName'
        : categoryName;
  }
}
