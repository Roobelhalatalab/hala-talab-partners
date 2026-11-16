# الملاحظة 24 — تدقيق صلاحيات الحفظ الموحد (مراجعة فقط)

المصدر: `HALA_TALAB_PARTNERS_NOTE24_NULL_GUARD_REVIEW_ONLY.zip`، ولا توجد تغييرات على Supabase أو GitHub.

## نتائج مؤكدة من SQL داخل الأرشيف

- `hala_save_complete_product_v1`: `SECURITY INVOKER` وتستدعي أربع دوال؛ لا يحتوي ملفها على GRANT فعّال (التعليق لا ينفّذ شيئًا).
- `hala_save_complete_single_shift_product_v1`: `SECURITY DEFINER`، يتحقق من `auth.uid()` وملكية المتجر وأن `shift_mode=1`، ويحتوي على `REVOKE` و`GRANT EXECUTE TO authenticated`.
- `hala_save_product_with_shifts`: يحوي `GRANT EXECUTE TO authenticated`.
- غياب GRANT صريح في ملف SQL **لا يثبت** عدم القدرة على التنفيذ؛ في PostgreSQL قد تُمنح EXECUTE لـ PUBLIC افتراضيًا، وقد تتدخل صلاحيات سابقة. يجب فحص قاعدة البيانات نفسها.
- `SECURITY INVOKER` لا يمنح الدالة تلقائيًا صلاحيات دوال `SECURITY DEFINER` التابعة؛ استدعاء الدوال يتطلب صلاحية EXECUTE للدور الفعلي.
- التراجع الذري داخل دالة PostgreSQL ينطبق على تغييرات قاعدة البيانات فقط، وليس ملفات الصور المرفوعة إلى Storage.

## إجراء مقترح

1. فحص الصلاحيات الفعلية بالدالة الاستعلامية المرفقة `NOTE24_FUNCTION_PERMISSIONS_PRECHECK_READ_ONLY.sql` (اختياري، قراءة فقط).
2. مراجعة ملكية و`search_path` لكل دالة SECURITY DEFINER ومراجعة أي وظائف جانبية/Triggers.
3. فحص العلاقات الخارجية إلى `product_variants` قبل السماح بحذف وإعادة إنشاء سجلاتها.
4. إجراء اختبارات فشل متعمد على قاعدة تجريبية منفصلة، مع التحقق من عدم تغيّر المنتج والأنواع والإضافات والترتيب بعد الفشل.

**قرار المراجعة:** لا نشر ولا تشغيل SQL تعديلي حتى اكتمال فحص الصلاحيات والتجربة. لم نغيّر كود التطبيق في هذه الجولة.
