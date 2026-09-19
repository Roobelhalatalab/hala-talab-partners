# تجهيز iOS – هلا طلب – الشركاء

تم تجهيز المشروع على Windows قبل الانتقال إلى Mac/Xcode:

- Bundle ID: `com.halatalab.partners`
- اسم التطبيق على iOS: `هلا طلب – الشركاء`
- Minimum iOS: 14.0
- الإصدار الحالي في pubspec: `1.0.0+2`
- `GoogleService-Info.plist` موجود ومتطابق مع Bundle ID.
- Firebase Messaging موجود في المشروع.
- `remote-notification` و `fetch` موجودان ضمن Background Modes في Info.plist.
- صلاحية الموقع موجودة.
- صلاحية مكتبة الصور موجودة للصور/المستندات التي يختارها المتجر.
- Waze مضاف ضمن `LSApplicationQueriesSchemes`.
- تم استبدال أيقونات Flutter الافتراضية بأيقونة هلا طلب – الشركاء.
- تم تجهيز Launch Image بدون شعار Flutter.
- تم إضافة Podfile وضبط iOS 14.

## ما يبقى على Mac/Xcode

1. `flutter pub get`
2. `cd ios && pod install && cd ..`
3. فتح `ios/Runner.xcworkspace` في Xcode.
4. اختيار Apple Developer Team وضبط Signing.
5. تفعيل Push Notifications capability وBackground Modes المطلوبة.
6. التأكد من APNs/Firebase Messaging على جهاز iPhone فعلي.
7. اختبار المتجر والسائق والخرائط والإشعارات.
8. Archive ثم الرفع إلى App Store Connect / TestFlight.

ملاحظة: الطباعة الحرارية المباشرة (Bluetooth/USB/Network المباشر) معرفة في الكود كميزة Android فقط؛ على iOS يستخدم التطبيق طباعة النظام عبر حزمة `printing`.
