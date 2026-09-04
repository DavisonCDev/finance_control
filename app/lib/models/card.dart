class CardModel {
  final int id;
  final String name;
  final String? brand;
  final double limitAmount;
  final int? closingDay;
  final int? dueDay;

  CardModel({
    required this.id,
    required this.name,
    this.brand,
    required this.limitAmount,
    this.closingDay,
    this.dueDay,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      limitAmount: double.tryParse(json['limit_amount'].toString()) ?? 0.0,
      closingDay: json['closing_day'],
      dueDay: json['due_day'],
    );
  }
}
