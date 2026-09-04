import 'package:flutter/material.dart';

class Budget {
  final int id;
  final int categoryId;
  final String categoryName;
  final String categoryColor;
  final String budgetMonth;
  final double amount;

  Budget({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.budgetMonth,
    required this.amount,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      categoryId: json['category_id'],
      categoryName: json['category_name'],
      categoryColor: json['category_color'] ?? '#000000',
      budgetMonth: json['budget_month'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
    );
  }

  Color getColor() {
    final hex = categoryColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}
