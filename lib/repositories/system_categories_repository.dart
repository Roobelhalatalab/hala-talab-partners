import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartnerSystemCategory {
  const PartnerSystemCategory({
    required this.id,
    required this.nameAr,
    this.nameKu,
    this.nameEn,
    this.categoryKey,
    this.icon,
    required this.sortOrder,
  });

  final String id;
  final String nameAr;
  final String? nameKu;
  final String? nameEn;
  final String? categoryKey;
  final String? icon;
  final int sortOrder;

  String labelFor(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'ku' && (nameKu ?? '').trim().isNotEmpty) return nameKu!.trim();
    if (code == 'en' && (nameEn ?? '').trim().isNotEmpty) return nameEn!.trim();
    return nameAr.trim();
  }

  String get legacyBusinessType {
    switch ((categoryKey ?? '').trim()) {
      case 'restaurants': return 'restaurant';
      case 'grocery': return 'grocery';
      case 'desserts': return 'sweets';
      case 'pharmacies': return 'pharmacy';
      case 'cafes': return 'cafe';
      case 'hookah': return 'hookah';
      case 'beverages': return 'beverages';
      case 'flowers': return 'flowers';
      default: return 'general';
    }
  }

  factory PartnerSystemCategory.fromMap(Map<String, dynamic> row) {
    return PartnerSystemCategory(
      id: row['id'].toString(),
      nameAr: (row['name_ar'] ?? '').toString(),
      nameKu: row['name_ku']?.toString(),
      nameEn: row['name_en']?.toString(),
      categoryKey: row['category_key']?.toString(),
      icon: row['icon']?.toString(),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class SystemCategoriesRepository {
  SystemCategoriesRepository._();
  static final instance = SystemCategoriesRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<PartnerSystemCategory>> activeCategories() async {
    final rows = await _client
        .from('system_categories')
        .select('id,name_ar,name_ku,name_en,category_key,icon,sort_order,is_active')
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => PartnerSystemCategory.fromMap(Map<String, dynamic>.from(row as Map)))
        .where((category) => category.nameAr.trim().isNotEmpty)
        .toList(growable: false);
  }
}
