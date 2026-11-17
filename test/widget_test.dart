import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hala_talab_partners/app/hala_talab_partners_app.dart';

void main() {
  testWidgets('partner role screen loads', (tester) async {
    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();

    expect(find.text('مرحباً بك في هلا طلب'), findsOneWidget);
    expect(find.byKey(const Key('business-role-card')), findsOneWidget);
    expect(find.byKey(const Key('driver-role-card')), findsOneWidget);
    expect(find.byKey(const Key('language-menu')), findsOneWidget);
  });

  testWidgets('business login screen opens', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('business-role-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-title')), findsOneWidget);
    expect(find.byKey(const Key('login-card')), findsOneWidget);
    expect(find.text('صاحب متجر'), findsOneWidget);
    expect(find.text('متابعة باستخدام Apple'), findsOneWidget);
    expect(find.byKey(const Key('language-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('language can change to Kurdish without an exception', (tester) async {
    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('language-menu')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کوردی').last);
    await tester.pumpAndSettle();

    expect(find.text('بەخێربێیت بۆ هەلا تەڵەب'), findsOneWidget);
    expect(find.text('چوونەژوورەوە وەک خاوەن فرۆشگا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language can change to English', (tester) async {
    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('language-menu')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Hala Talab'), findsOneWidget);
    expect(find.text('Continue as a store owner'), findsOneWidget);
  });
  testWidgets('create account screen opens from welcome', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('إنشاء حساب جديد'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signup-title')), findsOneWidget);
    expect(find.byKey(const Key('signup-card')), findsOneWidget);
    expect(find.byKey(const Key('business-type-dropdown')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver signup hides business type', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HalaTalabPartnersApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء حساب جديد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signup-driver-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('business-type-dropdown')), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
