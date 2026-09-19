# Hala Talab Partners

تطبيق هلا طلب الموحد لصاحب المطعم والسائق.

## المرحلة الحالية
- شاشة البداية والهوية البصرية.
- اختيار الدخول كصاحب مطعم أو كسائق.
- تصميم متجاوب للهاتف وWindows.
- ربط بطاقتي الاختيار بصفحة مؤقتة تمهيدًا لشاشة تسجيل الدخول في المرحلة التالية.

## التشغيل
```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

## Supabase

راجع `SUPABASE_SETUP.md` ثم شغّل `supabase/setup.sql` في SQL Editor قبل اختبار إنشاء الحساب.

Stage 124: Driver Email OTP + 4-digit PIN and authoritative role gate. See README_STAGE_124_DRIVER_EMAIL_OTP_PIN_AR.md

## Stage 155
راجع `README_STAGE_155_VARIANTS_ORDER_FINAL_AR.md` وشغّل `supabase/stage_155_product_variants_ordering.sql` مرة واحدة قبل اختبار الأحجام والترتيب.

## Stage 156
Use `supabase/stage_156_product_variants_ordering_final.sql`. This migration has no pg_temp dependency and is the authoritative variants/order migration.


## Stage 165
راجع `README_STAGE_165_PUSH_ROUTER_FIX_AR.md` لإصلاح توجيه Push للعميل/المتجر/السائق.
