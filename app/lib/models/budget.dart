import 'package:flutter/material.dart';

class Budget {
  final int id;
  final int categoryId;
  final String categoryName;
  final String categoryColor;
  final String? categoryIcon;
  final String budgetMonth;
  final double amount;
  final double spent;
  final double remaining;

  Budget({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    this.categoryIcon,
    required this.budgetMonth,
    required this.amount,
    this.spent = 0,
    this.remaining = 0,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      categoryId: json['category_id'],
      categoryName: json['category_name'],
      categoryColor: json['category_color'] ?? '#000000',
      categoryIcon: json['category_icon'],
      budgetMonth: json['budget_month'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      spent: double.tryParse(json['spent']?.toString() ?? '0') ?? 0.0,
      remaining: double.tryParse(json['remaining']?.toString() ?? '0') ?? 0.0,
    );
  }

  Color getColor() {
    final hex = categoryColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}
