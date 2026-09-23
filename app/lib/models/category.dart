import 'package:flutter/material.dart';

class Category {
  final int id;
  final int? parentId;
  final String name;
  final String type;
  final String color;
  final String icon;
  final int sortOrder;
  final bool isSystem;
  final String? pcCode;
  final String? pcGroup;

  Category({
    required this.id,
    this.parentId,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    this.sortOrder = 0,
    this.isSystem = false,
    this.pcCode,
    this.pcGroup,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      parentId: json['parent_id'],
      name: json['name'],
      type: json['type'],
      color: json['color'] ?? '#000000',
      icon: json['icon'] ?? 'category',
      sortOrder: json['sort_order'] ?? 0,
      isSystem: json['is_system'] == 1 || json['is_system'] == true,
      pcCode: json['pc_code'],
      pcGroup: json['pc_group'],
    );
  }

  Color getColor() {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isSubcategory => parentId != null;
}
