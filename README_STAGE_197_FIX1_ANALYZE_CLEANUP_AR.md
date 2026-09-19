# Stage 197 FIX1 — Analyze Cleanup

القاعدة: Stage 196 المعتمدة، مع تنظيف Stage 197 المحافظ.

تم في FIX1 معالجة التحذيرات الظاهرة في flutter analyze فقط بدون تغيير منطق المتجر أو السائق:
- تنظيف معاملات errorBuilder غير الضرورية.
- إزالة بقايا wizard غير المستخدمة (_step / _validateStep / _buildStep).
- استبدال DropdownButtonFormField.value بـ initialValue.
- تحسين constructor داخلي بدون تغيير السلوك.
- إضافة mounted guard قبل فتح محرر الصور بعد await.
- إضافة braces لتحذيرات if الظاهرة.
- إعادة صياغة metadata للتسجيل بدون collection-if lint.
- استبدال Matrix4.translate القديمة بـ translateByDouble.

يجب تشغيل flutter analyze على جهاز التطوير للتأكد من النتيجة النهائية.
