# اختبار المصادقة النهائي — Stage 49 / 140

بعد تشغيل SQL الموحد مرة واحدة فقط:

1. عميل صحيح داخل Client: يسمح بإرسال OTP.
2. متجر داخل Client: رفض قبل OTP.
3. سائق داخل Client: رفض قبل OTP.
4. متجر صحيح داخل Partners/Store: يسمح بإرسال OTP.
5. سائق داخل Store: رفض قبل OTP.
6. سائق صحيح داخل Partners/Driver: يسمح بإرسال OTP.
7. متجر داخل Driver: رفض قبل OTP.
8. بريد غير مسجل في Login: لا ينشئ Auth User ولا يرسل OTP.
9. بريد غير مسجل في Signup: ينشئ الحساب ويرسل OTP.
10. بريد موجود في Signup: لا ينشئ حسابًا ثانيًا.

نتيجة SQL الصحيحة:
- final_account_registry_ready = true
- infer_function_versions = 1
- unknown_users يفضّل أن يكون 0. إذا كان أكبر من 0، لا تحذف أي حساب؛ هذه حسابات قديمة تحتاج تحديد الدور قبل السماح بالدخول.

## Stage 193 — WhatsApp phone auth
1. متجر جديد: رقم جديد -> WhatsApp OTP -> إنشاء الحساب -> onboarding.
2. سائق جديد: رقم جديد -> WhatsApp OTP -> إنشاء الحساب -> driver home/onboarding.
3. إغلاق التطبيق وفتحه: لا OTP ولا PIN، تفتح الجلسة تلقائيًا.
4. تسجيل خروج صريح: الجلسة تُحذف؛ الدخول التالي يحتاج WhatsApp OTP.
5. رقم متجر في شاشة السائق: مرفوض ROLE_MISMATCH_BUSINESS.
6. رقم سائق في شاشة المتجر: مرفوض ROLE_MISMATCH_DRIVER.
7. رقم عميل: مرفوض ROLE_MISMATCH_CUSTOMER.
8. حساب معلّق إداريًا: مرفوض ACCOUNT_SUSPENDED.
