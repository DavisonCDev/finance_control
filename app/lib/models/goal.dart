class Goal {
  final int id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? deadline;

  Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.deadline,
  });

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'],
      name: json['name'],
      targetAmount: double.tryParse(json['target_amount'].toString()) ?? 0.0,
      currentAmount: double.tryParse(json['current_amount'].toString()) ?? 0.0,
      deadline: json['deadline'] != null ? DateTime.parse(json['deadline']) : null,
    );
  }

  double get percent => targetAmount > 0 ? (currentAmount / targetAmount) * 100 : 0;
}
