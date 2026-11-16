# Stage 215 — Partners Android PIN Security

التعديل:
- استبدال تغيير كلمة المرور/البريد بـ "تغيير PIN".
- تغيير PIN من داخل التطبيق: PIN الحالي + PIN الجديد + التأكيد.
- زر "نسيت PIN؟" داخل شاشة تغيير PIN.
- نسيت PIN يستخدم نفس نظام تسجيل الدخول الحالي:
  يرسل طلبًا إلى لوحة الإدارة، ثم يمكن للإدارة إصدار رمز الاسترجاع والتواصل مع صاحب الحساب/السائق أو إرساله عبر واتساب.
- إضافة نفس خيار تغيير PIN إلى حساب السائق.
- إزالة البريد الوهمي من سطر تغيير بيانات الدخول.
- لا توجد تعديلات على الطباعة أو الإشعارات أو الطلبات أو الخرائط أو Presence.

مهم قبل الاختبار:
- لا يوجد SQL جديد.
- يجب إعادة نشر Edge Function الموجودة:
  supabase/functions/phone-pin-auth/index.ts
  لأن تمت إضافة action آمنة باسم change_pin.
- لا تغيّر إعداد Verify JWT الحالي للـFunction؛ خلي الإعداد مثل ما هو لأن نفس Function تخدم تسجيل الدخول ونسيت PIN.

الملفات المعدلة:
1. lib/screens/dashboard/partner_dashboard.dart
2. lib/screens/dashboard/settings_profile.dart
3. lib/screens/dashboard/driver_account_center.dart
4. lib/services/phone_pin_partner_auth_service.dart
5. supabase/functions/phone-pin-auth/index.ts
