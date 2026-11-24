نسخة مصححة لإعداد مشروع ChatGPT-iOS على GitHub Actions

محتويات الحزمة:
1) ChatGPT-iOS-GitHub-ready.zip
   أرشيف المشروع وفي داخله ChatGPT-iOS/project.yml المضاف.
2) .github/workflows/ios-build.yml
   Workflow محدث يفك الأرشيف، يتحقق من وجود ملفات Swift، يولد مشروع Xcode، يبني Archive غير موقع، ثم ينشئ IPA ويرفعه كـ Artifact.

طريقة الاستعمال:
- فك ضغط هذه الحزمة.
- ارفع/استبدل ChatGPT-iOS-GitHub-ready.zip في جذر مستودع GitHub.
- ارفع/استبدل .github/workflows/ios-build.yml في نفس المسار.
- اعمل Commit إلى main ثم شغل GitHub Actions.
- عند نجاح Build، نزّل Artifact باسم ChatGPT-unsigned-IPA.
- هذا IPA غير موقع؛ وقّعه بشهادتك عبر ESign/WSign.

ملاحظة:
تم إصلاح إعدادات المشروع ومسارات التجميع بناءً على بنية الملفات داخل الأرشيف. لم يتم تنفيذ Xcode build هنا لأن بناء تطبيق iOS يتطلب macOS وXcode؛ نجاح الـ Compilation النهائي لا يمكن تأكيده قبل تشغيل GitHub Actions.
