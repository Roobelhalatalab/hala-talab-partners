# NOTE24 – camera for product, variant and category photos (REVIEW ONLY)

Source: HALA_TALAB_PARTNERS_NOTE24_SAFE_IMAGE_CLEANUP_REVIEW_ONLY.zip.

Changes: added camera/gallery bottom sheet using existing image_picker dependency and PlatformFile conversion. Applied to product image, product variant image, and category image. Existing crop editor, 5MB validation, uploads and image cleanup remain untouched. Existing gallery-only helper remains available for other screens.

iOS already declares NSCameraUsageDescription. Android uses image_picker camera intent; no new broad camera permission requested. Camera availability, permissions and device testing are NOT verified. No SQL or backend changes. Do not deploy without Flutter analyze/build and Android/iOS device tests (camera, gallery, crop, cancel, denied permission, save and image replacement).
