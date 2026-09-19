# تفعيل Push Notifications قبل الإطلاق
1. إنشاء/استخدام Firebase Project خاص بهلا طلب.
2. إضافة Android app بنفس applicationId الموجود في المشروع، وتنزيل `google-services.json` ووضعه في `android/app/`.
3. إضافة iOS app بنفس Bundle ID، وتنزيل `GoogleService-Info.plist` وإضافته إلى Runner عبر Xcode.
4. تفعيل Firebase Cloud Messaging وAPNs للـiOS.
5. نشر `supabase/functions/send-push`.
6. إضافة أسرار FCM الخاصة بالخادم للـEdge Function. لا تضع أسرار الخادم داخل تطبيق Flutter.
7. اختبار: التطبيق مفتوح / بالخلفية / مغلق + الضغط على الإشعار.
