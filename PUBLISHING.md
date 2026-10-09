# دليل النشر: GitHub و Google Play

رقم الحزمة: **`com.blackringsecurity.nabby`** (ما يتغير بعد أول رفع على جوجل بلاي).

## 1. رفع المشروع على GitHub (مرة وحدة)

```bash
cd nabby
gh repo create Black-Ring-Security/nabby --public --source . --push \
  --description "Free, open source SSH & SFTP client for Android. Edit BY Black Ring Security" \
  --homepage "https://black-ring-security.github.io/nabby/"
bash tool/setup_github_secrets.sh Black-Ring-Security/nabby   # يرفع مفتاح التوقيع كأسرار مشفرة
```

بعدها من صفحة المستودع:
- **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `/docs` → Save**
  - الموقع يصير: https://black-ring-security.github.io/nabby/
  - سياسة الخصوصية: https://black-ring-security.github.io/nabby/privacy.html  ← هذا الرابط تحطه في جوجل بلاي
- **Settings → Security → Private vulnerability reporting → Enable** (عشان رابط SECURITY.md يشتغل)
- **About (الترس جنب الوصف) → Topics**: `ssh` `sftp` `terminal` `android` `flutter`

## 2. البناء

### من Android Studio
1. ثبّت إضافتي **Flutter** و **Dart**: Settings → Plugins.
2. افتح مجلد `nabby` كله (مو `android` بس).
3. **Build → Flutter → Build App Bundle**.
4. الملف: `build/app/outputs/bundle/release/app-release.aab`

### من الطرفية
```bash
flutter build appbundle --release
```

### أو من GitHub تلقائياً
```bash
git tag v1.0.0 && git push origin v1.0.0
```
GitHub Actions يبني APK و AAB موقّعين وينشرهم في صفحة **Releases**.

التوقيع يقرأ من `android/key.properties` و `android/app/nabby-release.jks`.
**خذ نسخة احتياطية منهم في مكان آمن ولا ترفعهم على GitHub.** (مستثنين في `.gitignore`.)

## 3. إنشاء التطبيق في Play Console
1. https://play.google.com/console ثم **Create app**.
2. الاسم `Nabby - SSH & SFTP Client`، النوع App، مجاني.
3. خلّي **Play App Signing** مفعّل. ملف `nabby-release.jks` يصير **upload key**.

## 4. البيانات المطلوبة
| القسم | الإجابة |
|---|---|
| Privacy policy | `https://black-ring-security.github.io/nabby/privacy.html` |
| Data safety | **No data collected, no data shared** |
| Ads | No ads |
| Content rating | جاوب الاستبيان (أداة، بدون محتوى حساس) |
| Target audience | 18+ |
| Category | Tools |
| App access | All functionality available without special access (ما فيه تسجيل دخول) |
| **Foreground service** | النوع: **Special use**. الوصف: "Keeps interactive SSH terminal sessions connected while the app is in the background, started only when the user opens a session". لازم فيديو قصير: تفتح جلسة، تطلع من التطبيق، الإشعار يظهر والجلسة تبقى شغالة |

## 5. ملفات المتجر (`fastlane/metadata/android/`)
| الملف | المكان في Play Console |
|---|---|
| `en-US/title.txt` و `ar/title.txt` | App name |
| `*/short_description.txt` | Short description |
| `*/full_description.txt` | Full description |
| `en-US/images/icon.png` | App icon 512×512 |
| `en-US/images/featureGraphic.png` | Feature graphic 1024×500 |
| `en-US/images/phoneScreenshots/` | لقطات الشاشة (2-8، مقاس 1080×2160) |
| `*/changelogs/<versionCode>.txt` | Release notes |

أضف العربية من **Store presence → Main store listing → Manage translations → Arabic**.

## 6. الاختبار قبل النشر
**حساب المطور الشخصي الجديد:** جوجل تشترط **اختبار مغلق مع 12 مختبر لمدة 14 يوم** قبل النشر للعامة.
1. Testing → Closed testing → أنشئ track، ارفع الـ AAB، أضف إيميلات المختبرين.
2. بعد 14 يوم: Production → Apply for production.
(حساب منظمة ما عليه هذا الشرط.)

## 7. التحديثات
1. عدّل الكود.
2. ارفع النسخة في `pubspec.yaml`: `version: 1.0.1+2`. **الرقم بعد `+` لازم يزيد كل مرة.**
3. اكتب ملاحظات التحديث في `fastlane/metadata/android/en-US/changelogs/2.txt` (و `ar`) و `CHANGELOG.md`.
4. `git commit`، بعدها `git tag v1.0.1 && git push origin main v1.0.1`.
5. حمّل الـ AAB من GitHub Releases (أو ابنه محلياً) وارفعه: Play Console → Production → Create new release.

بعد مراجعة جوجل:
- جوجل بلاي **يحدّث التطبيق تلقائياً** للمستخدمين.
- داخل التطبيق يطلع **"Update downloaded → RESTART"** أول ما يفتحه المستخدم.
- في الإعدادات زر **Check for updates**.
- اللي ثبتوا الـ APK من GitHub يحدّثون يدوياً من صفحة Releases.

**كل تحديث لازم يكون موقّع بنفس `nabby-release.jks`.**
