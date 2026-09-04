import 'package:flutter/material.dart';

class Category {
  final int id;
  final String name;
  final String type;
  final String color;
  final String icon;

  Category({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      color: json['color'] ?? '#000000',
      icon: json['icon'] ?? 'category',
    );
  }

  Color getColor() {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}
