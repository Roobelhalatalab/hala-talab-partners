# هلا طلب — الملاحظة 24: تدقيق سلامة معرّفات الأنواع (REVIEW ONLY)

## الدليل من النسخة الأصلية
- `supabase/partners_stage_219_phase2_store_features_safe.sql`: الدالة `store_replace_product_variants_v3` تنفذ `DELETE FROM public.product_variants WHERE product_id = p_product_id` ثم INSERT، وبالتالي تغيّر كل UUID عند كل تعديل.
- `supabase/stage_156_product_variants_ordering_final.sql`: عمود `is_available` موجود في جدول `product_variants`، لذلك يمكن إخفاء النوع بدل حذفه.
- CSV الذي أرسله المستخدم: يوجد FK من `order_items.variant_id` إلى `product_variants.id` مع `ON DELETE SET NULL`، لذلك الحذف يفقد المرجع التاريخي.
- `NOTE24_UNIFIED_COMPLETE_PRODUCT_SAVE_REVIEW_ONLY.sql` و`NOTE24_SINGLE_SHIFT_UNIFIED_SAVE_REVIEW_ONLY.sql`: كلا المسارين يستدعيان v3 المدمرة.
- `lib/repositories/products_repository.dart`: `getProductVariants` يسترجع id، لكن مسار نسخ المنتج يرسل قائمة بلا id (صحيح للنسخ). يجب فحص مسار تعديل المنتج وتضمين id للأنواع الموجودة.

## القرار الآمن
1. كتابة دالة جديدة **v4** تحفظ `id` للأنواع القائمة، وتحدّثها بـ UPDATE بدل DELETE.
2. عند حذف نوع من قائمة التاجر، يصبح `is_available=false`، مع إبقاء صفه ومرجعه في الطلبات.
3. عند إضافة نوع جديد، INSERT بمعرّف جديد. عند النسخ، لا يعاد استخدام ID من المنتج الأصلي.
4. تمييز تعديل الاسم عن حذف نوع وإضافة آخر بواسطة `id` الصريح في طلب التعديل؛ المطابقة بالاسم وحده غير كافية.
5. يجب تدقيق فهارس UNIQUE على `(product_id, sort_order)` واسم النوع، وضبط الترتيب بدون اصطدام مؤقت.
6. تحديث استدعاءات الدالتين الموحدتين ومسار المستودع إلى v4 فقط بعد التحقق من إرسال ID في التعديل وعدم إرساله في النسخ.
7. إضافة اختبارات: تعديل سعر نوع مرتبط بطلب، إعادة تسمية، حذف منطقي، إعادة إظهار، تبديل الترتيب، نوع جديد، نسخ المنتج، فشل المعاملة، الشفت الواحد والشفتين.

## نتيجة الجولة
هذه الجولة **تدقيق موثّق وليست إصلاحًا مكتملًا**. لم يتم تغيير أي ملف من مشروع الشركاء أو تشغيل SQL. لا تشغّل v3 أو SQL الموحد على الإنتاج قبل إصلاح مسار الأنواع واختباره.
