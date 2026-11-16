# هلا طلب — ترتيب ملفات SQL المقترحة للملاحظة 24 (للمراجعة فقط)

**ممنوع تشغيل هذه الملفات على قاعدة الإنتاج حاليًا.** الترتيب يحدد اعتماد الدوال فقط، ولا يعني نجاحها أو جاهزيتها للنشر.

1. `supabase/note_24_menu_mode_schema_REVIEW_ONLY.sql` — متطلبات وضع المنيو (يحتاج مراجعة قبل التنفيذ).
2. `NOTE24_ATOMIC_SHIFT_LINKS_REVIEW_ONLY.sql` — ربط الشفتات.
3. `NOTE24_ATOMIC_CATEGORY_SAVE_REVIEW_ONLY.sql` — حفظ الأقسام.
4. `NOTE24_CATEGORY_SHIFT_TRIGGER_PATCH_REVIEW_ONLY.sql` — توافق روابط الأقسام القديمة.
5. `NOTE24_ATOMIC_PRODUCT_SAVE_REVIEW_ONLY.sql` — حفظ بيانات المنتج وروابط الشفتات.
6. `NOTE24_ATOMIC_ADDON_LINKS_REVIEW_ONLY.sql` — روابط الإضافات.
7. `NOTE24_PRESERVE_VARIANT_IDS_V4_REVIEW_ONLY_DO_NOT_RUN.sql` — حفظ الأنواع دون تغيير معرّفاتها.
8. `NOTE24_UNIFIED_COMPLETE_PRODUCT_SAVE_REVIEW_ONLY.sql` — حفظ الشفتين (يعتمد على الدوال السابقة ودالة `store_set_product_position_v6` الموجودة).
9. `NOTE24_SINGLE_SHIFT_UNIFIED_SAVE_REVIEW_ONLY.sql` — حفظ الشفت الواحد (نفس الاعتماديات).

## ما تغيّر بهذه الدفعة
- أضيف إلى دالة الحفظ الموحد للشفتين فحص `auth.uid()` وملكية المتجر و`shift_mode = 2` مع قفل صف المتجر.
- حُددت صلاحيات EXECUTE لدور `authenticated` فقط ضمن مسودة SQL.
- لم تُشغّل أي دالة ولم تتغير بيانات Supabase أو GitHub.

## ما لم يثبت بعد
- توافق جميع التعريفات مع قاعدة اختبارية، وتشغيل Flutter، وتوافق RLS والتريغرات.
- الدوال القديمة الموجودة في الإنتاج لا تتغير بهذه المسودات.
