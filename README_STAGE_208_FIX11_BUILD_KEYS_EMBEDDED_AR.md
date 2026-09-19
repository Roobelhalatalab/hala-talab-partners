# Stage 208 Fix11 — Build Keys Embedded

هذه النسخة مبنية على Fix10 Signing Ready.

التعديل الوحيد في Fix11:
- تثبيت إعدادات بناء العميل العامة داخل `lib/core/build_config.dart` بحيث يعمل Release بدون الحاجة لكتابة `--dart-define` يدويًا كل مرة.
- القيم المثبتة: Supabase URL، Supabase publishable/anon key، وMapbox public access token.
- ما زال `--dart-define` مدعومًا، وإذا تم تمريره فإنه يتغلب على القيمة الافتراضية.
- لا يوجد Service Role key أو مفتاح خادم سري داخل التطبيق.
- لم يتم تعديل الطلبات أو الطباعة أو الإشعارات أو الخرائط أو المصادقة أو قاعدة البيانات.
