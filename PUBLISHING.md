# دليل النشر على Google Play

## 1. البناء

### من Android Studio
1. ثبّت إضافتي **Flutter** و **Dart** من: Settings → Plugins.
2. افتح مجلد `nabby` كله (مو مجلد `android` بس): File → Open → `nabby`.
3. القائمة: **Build → Flutter → Build App Bundle**.
4. الملف يطلع هنا: `build/app/outputs/bundle/release/app-release.aab`

### أو من الطرفية
```bash
flutter build appbundle --release
```

التوقيع جاهز تلقائياً من `android/key.properties` و `android/app/nabby-release.jks`.
**خذ نسخة احتياطية من هذين الملفين في مكان آمن ولا ترفعهما على GitHub أبداً.**
(هما مستثنيان في `.gitignore` أصلاً.)

## 2. إنشاء التطبيق في Play Console
1. https://play.google.com/console ثم **Create app**.
2. الاسم: `Nabby - SSH & SFTP Client`، النوع App، مجاني.
3. فعّل **Play App Signing** (الافتراضي). ملف `nabby-release.jks` يصير **upload key**.
   إذا ضاع، تطلب من جوجل upload key جديد. ولكن لا تضيّعه.

## 3. البيانات المطلوبة
| القسم | الإجابة |
|---|---|
| Privacy policy | ارفع `PRIVACY_POLICY.md` على GitHub Pages أو أي رابط عام. ولا تنسى تغيير `[CONTACT_EMAIL]` |
| Data safety | **No data collected, no data shared**. البيانات مشفرة وتبقى في الجهاز |
| Ads | No ads |
| Content rating | جاوب الاستبيان (أداة، بدون محتوى حساس) |
| Target audience | 18+ |
| Category | Tools |
| **Foreground service** | النوع: **Special use**. الوصف: "Keeps interactive SSH terminal sessions connected while the app is in the background, started only when the user opens a session". لازم ترفع فيديو قصير يبين: تفتح جلسة، تطلع من التطبيق، الإشعار يظهر، والجلسة تبقى شغالة |

## 4. ملفات المتجر (مجلد `store/`)
- `icon-512.png`: أيقونة المتجر
- `feature-graphic-1024x500.png`: صورة الواجهة
- `en-US/listing.md` و `ar/listing.md`: الاسم والوصف المختصر والكامل
- لقطات الشاشة: من 2 إلى 8 لقطات. **لا يزيد الطول عن ضعف العرض**، يعني 1080×2160 للجوال

## 5. الاختبار قبل النشر
**حسابات المطورين الشخصية الجديدة:** جوجل تشترط **اختبار مغلق (Closed testing) مع 12 مختبر على الأقل لمدة 14 يوم** قبل ما يسمح لك بالنشر للعامة.
1. Testing → Closed testing → أنشئ track.
2. ارفع الـ AAB وأضف إيميلات المختبرين.
3. بعد 14 يوم: Production → Apply for production.
(حساب منظمة/شركة ما يحتاج هذا الشرط.)

## 6. التحديثات: كيف توصل للمستخدمين
1. عدّل الكود.
2. **ارفع رقم النسخة** في `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2   # الاسم+الرقم. الرقم بعد + لازم يزيد كل مرة
   ```
3. ابنِ AAB جديد وارفعه في Play Console (Production → Create new release).
4. بعد مراجعة جوجل (عادة ساعات إلى يومين):
   - جوجل بلاي **يحدّث التطبيق تلقائياً** عند المستخدمين.
   - وأول ما يفتح المستخدم التطبيق، يطلع له داخله **"Update downloaded → RESTART"** (in-app update) فيتحدث فوراً.
   - وفي الإعدادات زر **Check for updates**.

**مهم:** لازم كل تحديث يكون موقّع بنفس `nabby-release.jks`، والرقم بعد `+` أكبر من اللي قبله.

## 7. رقم الحزمة (Package name)
حالياً `com.nero.nabby`. **ما يتغير أبداً بعد أول رفع.** إذا تبي اسم الفريق مثل
`com.blackringsecurity.nabby` غيّره **قبل** أول رفع.
