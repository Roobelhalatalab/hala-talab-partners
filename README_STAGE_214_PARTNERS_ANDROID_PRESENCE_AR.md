# Stage 214 — Partners Android Presence

تمت إضافة Presence خفيفة لتطبيق هلا طلب – الشركاء على Android فقط.

## الملفات المعدلة
- lib/main.dart
- lib/services/online_presence_service.dart (ملف جديد)

## السلوك
- القناة المشتركة: hala_online_users
- إذا كان الحساب متجرًا: role = business
- إذا كان الحساب سائقًا: role = driver
- platform = android
- يتم التسجيل فقط للمستخدم المسجل دخوله والتطبيق في الواجهة.
- عند الخلفية/الإغلاق/تسجيل الخروج يتم إزالة Presence.

## لم يتم لمس
- Push / Firebase / FCM
- الطباعة Wi-Fi أو Bluetooth
- الطلبات
- الخرائط
- المصادقة أو PIN
- ملفات Android native
