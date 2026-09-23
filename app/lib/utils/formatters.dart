import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _brl = NumberFormat('#,##0.00', 'pt_BR');
final _brDate = DateFormat('dd/MM/yyyy');

/// Formata um número no padrão brasileiro: 1.234,56
String fmtMoney(num? value) => _brl.format(value ?? 0);

/// Converte ISO (2026-10-15...) ou DateTime para dd/MM/yyyy
String fmtDate(dynamic value) {
  if (value == null) return '-';
  final d = value is DateTime ? value : DateTime.tryParse(value.toString());
  return d == null ? value.toString() : _brDate.format(d);
}

/// Entrada de dinheiro estilo app de banco: digite só os dígitos.
/// "1" -> 0,01 | "12345" -> 123,45 | "1234567" -> 12.345,67
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final text = fmtMoney(int.parse(digits) / 100);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
