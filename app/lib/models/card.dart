class CardModel {
  final int id;
  final String name;
  final String? brand;
  final double limitAmount;
  final int? closingDay;
  final int? dueDay;
  final double usedLimit;
  final double availableLimit;
  final double futurePurchasesTotal;
  final Map<String, dynamic>? currentInvoice;

  CardModel({
    required this.id,
    required this.name,
    this.brand,
    required this.limitAmount,
    this.closingDay,
    this.dueDay,
    this.usedLimit = 0,
    this.availableLimit = 0,
    this.futurePurchasesTotal = 0,
    this.currentInvoice,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      limitAmount: double.tryParse(json['limit_amount'].toString()) ?? 0.0,
      closingDay: json['closing_day'],
      dueDay: json['due_day'],
      usedLimit: double.tryParse((json['used_limit'] ?? 0).toString()) ?? 0.0,
      availableLimit:
          double.tryParse((json['available_limit'] ?? 0).toString()) ?? 0.0,
      futurePurchasesTotal:
          double.tryParse((json['future_purchases_total'] ?? 0).toString()) ??
          0.0,
      currentInvoice: json['current_invoice'] as Map<String, dynamic>?,
    );
  }
}
