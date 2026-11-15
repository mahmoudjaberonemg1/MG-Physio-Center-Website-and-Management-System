# MG Physio Center — Supabase Connected

المشروع يحتوي على الموقع التعريفي ولوحة دخول فعلية مرتبطة بمشروع Supabase.

## الملفات
- `index.html`: الموقع + نموذج حجز يحفظ الطلب مباشرة في Supabase للمريض المسجل دخوله.
- `dashboard.html`: تسجيل الدخول/إنشاء حساب مريض، ولوحة منفصلة حسب صلاحية الحساب (owner / doctor / patient).
- `supabase_setup.sql`: إنشاء الجداول وسياسات RLS والصلاحيات.
- `assets/`: صور الموقع.

## خطوات التفعيل المطلوبة
1. افتح مشروع Supabase المرتبط بالموقع.
2. افتح SQL Editor.
3. الصق محتوى `supabase_setup.sql` كاملًا وشغّله.
4. افتح الموقع وأنشئ حساب المالك أولًا من `dashboard.html` (إنشاء حساب مريض).
5. بعد إنشاء الحساب، افتح SQL Editor وشغّل أمر ترقية حساب المالك بعد استبدال البريد:

```sql
update public.profiles set role = 'owner'
where id = (select id from auth.users where email = 'YOUR_OWNER_EMAIL');
```

6. لإنشاء حساب دكتور: أنشئ المستخدم من Supabase Dashboard > Authentication > Users، ثم اجعله دكتورًا:

```sql
update public.profiles set role = 'doctor'
where id = (select id from auth.users where email = 'DOCTOR_EMAIL');
```

7. من لوحة المالك، عيّن كل حجز إلى الدكتور المناسب. بعدها سيظهر الحجز للدكتور فقط، وسيستطيع تسجيل ملاحظات الجلسات.
8. في Supabase Authentication > URL Configuration، أضف رابط GitHub Pages إلى Site URL وRedirect URLs، مثل `https://YOUR-USERNAME.github.io/YOUR-REPOSITORY/`.

## الأمان
- المفتاح الموجود في ملفات الواجهة هو Publishable Key فقط، وهو مخصص للواجهة العامة. لا تضع `service_role` أو Secret Key في GitHub أو المتصفح.
- الصلاحيات الحقيقية مفروضة بسياسات Row Level Security في قاعدة البيانات، وليس بمجرد إخفاء أقسام الصفحة.
- حسابات التسجيل العامة تُنشأ بدور `patient` فقط. ترقية المالك والدكاترة تتم يدويًا من SQL بعد إنشاء الحساب.
- لا تدخل بيانات مرضى حقيقية قبل تشغيل SQL، وإعداد البريد/تأكيد الحساب، واختبار كل دور بحساب مستقل.
- GitHub Pages لا يرسل رسائل بريد أو WhatsApp تلقائيًا. الإشعارات الفورية داخل لوحة التحكم تعتمد على Realtime، أما رسائل WhatsApp/SMS فتحتاج تكاملًا خادميًا منفصلًا.

## ملاحظة تشغيل
إذا كان تأكيد البريد الإلكتروني مفعّلًا في Supabase، يجب على المستخدم تأكيد بريده قبل تسجيل الدخول. يمكن ضبط ذلك من Authentication > Providers > Email.
