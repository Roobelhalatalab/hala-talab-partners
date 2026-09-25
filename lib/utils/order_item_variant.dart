String orderItemVariantLabel(Map<String, dynamic> item) {
  String clean(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
  }

  for (final key in const [
    'variant_name',
    'selected_variant_name',
    'option_name',
    'size_name',
    'flavor_name',
    'variant',
    'size',
    'flavor',
  ]) {
    final raw = item[key];
    if (raw is Map) {
      for (final nestedKey in const ['name', 'title', 'label', 'value']) {
        final value = clean(raw[nestedKey]);
        if (value.isNotEmpty) return value;
      }
    } else {
      final value = clean(raw);
      if (value.isNotEmpty) return value;
    }
  }

  for (final key in const ['selected_variant', 'selected_option']) {
    final raw = item[key];
    if (raw is Map) {
      for (final nestedKey in const ['name', 'title', 'label', 'value']) {
        final value = clean(raw[nestedKey]);
        if (value.isNotEmpty) return value;
      }
    }
  }

  return '';
}

String orderItemDisplayName(Map<String, dynamic> item) {
  final productName =
      (item['product_name'] ?? item['name'] ?? '-').toString().trim();
  final variant = orderItemVariantLabel(item);
  if (variant.isEmpty) return productName.isEmpty ? '-' : productName;

  final normalizedProduct = productName.toLowerCase();
  final normalizedVariant = variant.toLowerCase();
  if (normalizedProduct.contains(normalizedVariant)) return productName;
  return '$productName - $variant';
}
