# دليل هندسة البرمجيات AI-First

دليل هندسي يركز على الإنتاجية في عصر الذكاء الاصطناعي.

لقد جعل الذكاء الاصطناعي كتابة الشيفرة البرمجية رخيصة. لم تعد عنق الزجاجة هي
الكتابة — بل أصبحت هي **الحكم الهندسي**: المعمارية، والمفاضلات، ومراجعة
مخرجات الذكاء الاصطناعي، وشحن أنظمة تصمد أمام المستخدمين الحقيقيين. يعلّمك
هذا الدليل ذلك الحكم.

> **هل أنت جديد هنا وتريد التعلم منه؟** اقرأ **[START-HERE.md](START-HERE.md)** —
> دليل قراءة يغطي ما يجب قراءته، وبأي ترتيب، وكيف تتعلم منه فعليًا
> (وليس مجرد تصفحه). المراحل 1–10 جاهزة الآن.

## ما هو هذا الدليل

- دليل هندسي، وليس برنامجًا تعليميًا وليس توثيقًا.
- منهج تدريجي: عقلية ← معمارية ← بناء ← شحن ← توسع.
- AI-First: يُعامَل الذكاء الاصطناعي كزميل يعمل على تسريع التنفيذ.
  يتحمل المهندس مسؤولية كل قرار.

## ما ليس هذا الدليل

- ليس دورة في بناء الجملة. يجب أن تكون لديك بالفعل معرفة بالبرمجة الأساسية.
- ليس تسويقًا لأطر العمل. تتضمن التوصيات دائمًا متى *لا* تستخدم شيئًا ما.
- ليست أمثلة تافهة. كل مثال يشبه برمجيات شركة حقيقية.

## لمن هذا الدليل

المهندسون المبتدئون ومتوسطو الخبرة، ومؤسسو منتجات الـ SaaS، والهاكرز
المستقلون، وأي مطوّر ينتقل إلى سير عمل AI-First ويرغب في بناء أنظمة إنتاجية —
لا مجرد توليد شيفرة برمجية.

## كيفية قراءته

تبني المراحل على بعضها البعض. اقرأها بالترتيب في المرة الأولى؛ ثم ارجع إلى
أي فصل كمرجع لاحقًا. يتبع كل فصل نفس البنية: النموذج الذهني أولًا، ثم
مثال إنتاجي حقيقي، ثم المفاضلات، والأخطاء (البشرية وتلك الناتجة عن الذكاء
الاصطناعي)، وأفضل الممارسات، وشجرة قرار، وقوائم تحقق، وتمارين تشبه العمل
الهندسي الحقيقي.

يمكنك قراءة ملفات Markdown مباشرة، أو تقديم الدليل كموقع محلي مع تنقل
جانبي، وبحث نصي كامل، ووضع داكن:

```bash
./web/serve.sh        # requires uv — then open http://127.0.0.1:8000
```

## المنهج

| المرحلة | الموضوع | الحالة |
|---|---|---|
| 1 | [العقلية الهندسية](handbook/stage-01-engineering-mindset/README.md) | مكتمل |
| 2 | [هندسة البرمجيات والمعمارية](handbook/stage-02-software-architecture/README.md) | مكتمل |
| 3 | [الهندسة الخلفية (Backend)](handbook/stage-03-backend-engineering/README.md) | مكتمل |
| 4 | [الهندسة الأمامية (Frontend)](handbook/stage-04-frontend-engineering/README.md) | مكتمل |
| 5 | [هندسة تطبيقات الجوال](handbook/stage-05-mobile-engineering/README.md) | مكتمل |
| 6 | [هندسة قواعد البيانات](handbook/stage-06-database-engineering/README.md) | مكتمل |
| 7 | [DevOps](handbook/stage-07-devops/README.md) | مكتمل |
| 8 | [الاختبار](handbook/stage-08-testing/README.md) | مكتمل |
| 9 | [الأمن](handbook/stage-09-security/README.md) | مكتمل |
| 10 | [هندسة الذكاء الاصطناعي](handbook/stage-10-ai-engineering/README.md) | مكتمل |
| 11 | [تصميم الأنظمة](handbook/stage-11-system-design/README.md) | مكتمل |
| 12 | [هندسة SaaS](handbook/stage-12-saas-engineering/README.md) | مكتمل |
| 13 | القيادة الهندسية | مخطط |
| 14 | دراسات حالة | مخطط |

القائمة الكاملة للمواضيع في كل مرحلة موجودة في [meta/02-curriculum.md](meta/02-curriculum.md).

## الأصول الهندسية

تعلّم الفصول الحكم الهندسي؛ تضغطه هذه الأصول للاستخدام اليومي:

- **[القوالب](templates/README.md)** — ADR، وطلب السحب (Pull Request)،
  وملخص المشروع، وبادئة CLAUDE.md لمستودعاتك AI-First الخاصة.
- **[قوائم التحقق](checklists/README.md)** — مراجعة الشيفرة (بما في ذلك
  قسم مخصص للشيفرة المولّدة بالذكاء الاصطناعي) وجاهزية الإنتاج.
- **[الأدلة التشغيلية](playbooks/README.md)** — عمليات شاملة من البداية
  إلى النهاية، تبدأ بـ [بدء مشروع AI-First](playbooks/starting-an-ai-first-project.md).

## بنية المستودع

```
meta/        Project constitution, vision, and curriculum — the rules everything follows
prompts/     Reusable prompts for generating and reviewing chapters
handbook/    The content, one folder per curriculum stage
templates/   Documents to copy and fill in: ADR, PR, project brief, CLAUDE.md starter
checklists/  Verification lists for moments of action: code review, production readiness
playbooks/   Step-by-step processes that tie the templates and checklists together
docs/        Design specs and implementation plans for the repo itself
web/         MkDocs config for reading the handbook as a local website
examples/    (planned) Invoicely reference implementation — the app the chapters build
starter-kits/ (planned) Clone-and-ship SaaS templates extracted from the reference app
```

يُعد `meta/00-CONSTITUTION.md` المرجع الأعلى. عند تعارض الوثائق:
الدستور > الرؤية > المنهج.

## المساهمة

اقرأ `meta/00-CONSTITUTION.md` و`CLAUDE.md` قبل كتابة أي شيء.
الفصول التي تتخطى الأقسام المطلوبة أو تستخدم أمثلة تافهة تُرفض
قصدًا — راجع `prompts/01-review-chapter.md` لمعرفة معيار المراجعة.
