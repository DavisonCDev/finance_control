double? parseMoney(String? value) {
  if (value == null || value.isEmpty) return null;
  final clean = value.contains(',')
      ? value.replaceAll('.', '').replaceAll(',', '.')
      : value.replaceAll(',', '.');
  return double.tryParse(clean);
}
