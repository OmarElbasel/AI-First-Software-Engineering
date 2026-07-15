# مونوليث، مونوليث معياري، وخدمات صغرى (Microservices)

## المقدمة

في حين أن الفصول الثلاثة السابقة كانت تدور حول كيفية تنظيم الكود *داخل* وحدة
قابلة للنشر، فإن هذا الفصل يدور حول عدد الوحدات القابلة للنشر التي يجب أن
تكون موجودة. إنه طيف واحد، يمتد من عملية واحدة إلى عمليات متعددة:

- **المونوليث (Monolith)** هو وحدة قابلة للنشر واحدة: قاعدة كود واحدة، عملية
  واحدة، عادةً قاعدة بيانات واحدة. تبنيه، تختبره، وتشحنه ككل.
- **المونوليث المعياري (Modular Monolith)** لا يزال وحدة قابلة للنشر واحدة، لكنه
  مقسم داخليًا إلى وحدات (modules) ذات حدود واضحة تتواصل عبر واجهات محددة بدلاً
  من الوصول إلى تفاصيل بعضها البعض. يحافظ على البساطة التشغيلية للمونوليث مع
  اكتساب معظم المزايا التنظيمية التي تُنسب عادةً إلى الخدمات الصغرى.
- **الخدمات الصغرى (Microservices)** هي وحدات متعددة قابلة للنشر بشكل مستقل،
  تمتلك كل منها بياناتها الخاصة، وتتواصل عبر الشبكة. تتيح النشر المستقل،
  والتوسع المستقل، واستقلالية الفريق — على حساب أن يصبح النظام نظامًا موزعًا،
  بكل ما يترتب على ذلك.

تُدرَّس هذه الثلاثة معًا لأن تعليم أحدها دون الأخرى يؤدي بالتحديد إلى النتائج
الخرافية التي ندمت عليها الصناعة طوال العقد الماضي. الدرس الطاغي لذلك العقد هو
موضوع هذا الفصل: **ابدأ من اليسار، وانتقل إلى اليمين فقط عندما تتطلب قوة محددة
ذلك.** المونوليث المعياري هو الحل الوسط المُهمَل الذي ينبغي لمعظم المنتجات
النامية أن تقضي فيه وقتًا طويلاً، والخدمات الصغرى أداة قوية لها فاتورة كبيرة
دفعها عدد كبير جدًا من الفرق قبل أن يكون لديهم الإيرادات الكافية لها.

هنا أيضًا تتوقف البنية المعمارية عن كونها متعلقة بالكود فحسب لتصبح متعلقة
بالعمليات — أول فصل في هذه المرحلة تظهر قراراته في خط أنابيب النشر (deployment
pipeline) لديك، وفترة المناوبة (on-call) لديك، وفاتورة السحابة لديك.

## لماذا هذا مهم

اخيار الطوبولوجيا قريب من باب ذي اتجاه واحد (المرحلة 1، الفصل 04). دمج
الخدمات مرة أخرى في مونوليث ممكن لكنه نادر ومؤلم؛ تقسيم المونوليث مشروع
بحد ذاته. لذلك فإن تكلفة الخطأ في هذا الاختيار عالية، وعادةً ما تُدفع في
أحد اتجاهين.

إذا وزّعت في وقت مبكر جدًا، فإنك تشتري كامل تكلفة النظام الموزع قبل أن تحصل
على فوائده: الشبكة تفشل بطرق لا تفشل بها استدعاءات الدوال (function calls)،
والمعاملات التي كانت `COMMIT` واحدًا تصبح ساغا (sagas) متعددة الخطوات، والعملية
المنطقية الواحدة تصبح سلسلة من الاستدعاءات عن بُعد التي يمكن أن تنتهي
مهلتها (timeout) كل منها، وكل خدمة تحتاج إلى نشر ومراقبة وتسجيل ومناوبة خاصة
بها. فريق مكوّن من ثلاثة أشخاص يُدير ثماني خدمات صغرى يقضي وقته في العمليات
الأنظمة موزعة وتصحيح الأخطاء بدلًا من المنتج — جرح ذاتي ألحق أضرارًا حقيقية
بالشركات.

إذا وزّعت في وقت متأخر جدًا، أو لم تفرض حدودًا داخلية أبدًا، فإن المونوليث
يتعفن ليصبح كرة طين كبيرة (big ball of mud): كل شيء يستورد كل شيء، تغيير
فريق واحد يكسر فريقًا آخر، يجب نشر الكل معًا واختباره معًا، والتوسع يعني
توسع الكل سواء كان عنق الزجاجة جزءًا صغيرًا أم لا.

يوجد المونوليث المعياري تحديدًا لتأجيل هذا الاخيار مع البقاء بصحة جيدة:
الحدود الداخلية المفروضة تمنحك قابلية الصيانة و*الخيار* لاستخراج خدمة لاحقًا،
دون دفع ثمن التوزيع حتى تطلب ذلك قوة حقيقية. هذا هو تفكير العكسية
(reversibility) من الفصل 04 في المرحلة 1 مطبقًا على أكبر نطاق — أبقِ الباب
المكلف مغلقًا حتى تعرف أي اتجاه تحتاج إلى المشي من خلاله.

البُعد الخاص بالذكاء الاصطناعي قوي بشكل غير معتاد هنا. تم تدريب المساعدين
خلال ذروة دورة الضجيج حول الخدمات الصغرى، لذلك فإن غريزتهم الافتراضية هي
*الإفراط في التوزيع* — يقترحون خدمات منفصلة لمشاكل تحتاج استدعاءات دوال — وعند
قيامهم بإنشاء خدمات، فإنهم ينتجون مونوليثات موزعة تتشارك قواعد البيانات وتجري
مكالمات تزامنية ثرثارة. دون توجيه، سيقوم المساعد بسعادة ببناء أسوأ ما في
العالمين.

## النموذج الذهني

الخيارات الثلاثة هي نقاط على طيف واحد، وكل خطوة إلى اليمين تقايض البساطة
بالاستقلالية:

```
   MONOLITH            MODULAR MONOLITH           MICROSERVICES
   one unit            one unit, hard             many units, each
                       internal boundaries        independently deployable

   ┌───────────┐       ┌───────────────┐          ┌────┐ ┌────┐ ┌────┐
   │ everything│       │ ┌──┐┌──┐┌──┐  │          │svc │ │svc │ │svc │
   │ together  │       │ │M1││M2││M3│  │          │ +DB│ │ +DB│ │ +DB│
   │  one DB   │       │ └──┘└──┘└──┘  │          └────┘ └────┘ └────┘
   └───────────┘       │   one DB      │            └──network──┘
                       └───────────────┘

   simplest            simple to run,             independent deploy/scale/team
   to build & run      modular inside             — but now a DISTRIBUTED SYSTEM

   ◄──────────────  simplicity          independence  ──────────────►
   ◄──────────────  low ops cost        high ops cost ──────────────►

   DEFAULT: start left. Move right only when a specific force requires it.
```

ثلاث أفكار تجعل الطيف قابلاً للاستخدام.

**السؤال الحاسم هو استقلالية النشر، وليس نظافة الكود.** يمكنك أن يكون لديك
كود جميل التنظيم في مونوليث (وهذا مونوليث معياري) وتشابك فظيع منتشر عبر
الخدمات (وهذا مونوليث موزع). الشيء الذي تمنحك إياه الخدمات الصغرى فعلاً هو
القدرة على نشر وتوسع وتوطين كل خدمة بشكل مستقل. إذا لم تكن بحاجة إلى تلك
الاستقلالية، فأنت لا تحتاج إلى خدمات صغرى — مهما كانت الحدود نظيفة.

**قاعدة البيانات المشتركة تحوّل الخدمات الصغرى إلى مونوليث موزع.** أهم قاعدة
في الفصل كله: يجب أن تمتلك الخدمات بياناتها. في اللحظة التي تقرأ فيها خدمتان
وتكتبان في نفس الجداول، فإنهما مقترنتان على مستوى البيانات، ويجب أن تتغيرا معًا،
وقد دفعت كامل تكلفة الشبكة والعمليات للتوزيع مع الاحتفاظ بكل اقتران المونوليث.
هذا هو الربع الأسوأ، وهو حيث تهبط الفرق غير الموجهة (والذكاء الاصطناعي) في
الغالب.

**الحدود تتآكل دون الإنفاذ.** حدود المونوليث المعياري ليست محمية بواسطة الشبكة
— لا شيء يمنع وحدة (module) من استيراد تفاصيل أخرى إلا الانضباط والأدوات.
دون الإنفاذ (واجهات الواجهة facade، فحص الاستيراد import-linting، فصل المخطط
schema)، فإن المونوليث المعياري يتحلل إلى مونوليث عادي، وتتبخر قيمة الخيار
التي كنت تحافظ عليها.

تعريف عملي:

> **هذه نقاط على طيف يمتد من وحدة قابلة للنشر واحدة إلى وحدات متعددة، تقايض
> البساطة التشغيلية باستقلالية النشر. الافتراضي هو مونوليث ينمو إلى مونوليث
> معياري؛ الخدمات الصغرى مُبرَّرة فقط بحاجة محددة للنشر المستقل، أو التوسع
> المستقل، أو ملكية الفريق — وفقط إذا كانت كل خدمة تمتلك بياناتها.**

## مثال إنتاجي

**Invoicely** هي الآن **مونوليث معياري**. تُشحن كتطبيق FastAPI واحد ضد قاعدة
بيانات PostgreSQL واحدة، لكنها داخليًا مقسمة إلى وحدات — `invoicing`، `payments`،
`reconciliation`، `notifications` — مع الحدود المبنية على الميزات من الفصل 02
التي تمت ترقيتها إلى حدود وحدات *مفروضة*. كل وحدة تعرض واجهة عامة وتخفي
تفاصيلها الداخلية؛ الوحدات لا تستورد أبدًا مستودعات بعضها البعض أو تستعلم
جداول بعضها البعض.

هذا هو المكان الصحيح لـ Invoicely. نشر واحد، قاعدة بيانات واحدة، مناوبة واحدة
— البساطة التشغيلية التي يحتاجها الفريق الصغير — مع بنية داخلية نظيفة بما
يكفي لفهم الوحدات وتغييرها واختبارها بشكل مستقل، و*استخراجها* لاحقًا إذا
ظهرت قوة حقيقية.

وتظهر واحدة. وحدة reconciliation تستهلك كثيرًا من وحدة المعالجة المركزية: الحسابات
الكبيرة تؤدي إلى تشغيل مطابقات تشغل العامل لدقائق، وخلال إقفال نهاية الشهر،
تعمل هذه التشغيلات على تجويع بقية واجهة API من السعة. تحتاج Invoicely إلى
توسع reconciliation *بشكل مستقل* عن طبقة الويب — قوة محددة حقيقية، وليست
موضة. لذلك تصبح reconciliation، وفقط reconciliation، خدمة منفصلة. تبقى الوحدات
الأخرى في المونوليث، لأنه لا شيء فيها يحتاج نشرًا أو توسعًا مستقلاً.

ثمار الفصول السابقة تهبط هنا: نظرًا لأن reconciliation كانت بالفعل وحدة نظيفة
بواجهة محددة (الفصلان 02 و03)، فإن الاستخراج تغيير قابل للتنفيذ بدلاً من أن
يكون مشروع تنقيب أثري. سننظر إلى حد الوحدة الذي يجعل هذا ممكنًا، وما يصبح
عليه هذا الحد عندما يتحول إلى قفزة شبكية (network hop).

## بنية المجلدات

```
# MODULAR MONOLITH — one deployable unit, hard internal boundaries
app/
├── modules/
│   ├── invoicing/
│   │   ├── public.py         # THE module's public interface (facade)
│   │   ├── _service.py       # internals — underscore-private by convention
│   │   ├── _repository.py
│   │   └── _models.py        # owns the `invoices` tables; no one else touches them
│   ├── payments/
│   │   ├── public.py
│   │   └── _...
│   ├── reconciliation/
│   │   ├── public.py         # the interface that will survive extraction
│   │   └── _...
│   └── notifications/
│       └── ...
├── core/                     # cross-cutting: config, db, auth, errors
└── main.py                   # mounts each module's routes

# AFTER EXTRACTION — reconciliation becomes its own service
deploy/
├── docker-compose.yml        # invoicely-api, reconciliation-svc, postgres, broker
services/
├── invoicely-api/            # the monolith, minus reconciliation internals
│   └── modules/reconciliation/public.py   # now an HTTP CLIENT, same interface
└── reconciliation-svc/       # the extracted service, its OWN database
    ├── app/
    └── Dockerfile
```

لماذا هذا الشكل:

- **`modules/`** يحل محل `features/` للإشارة إلى أن هذه الحدود مفروضة، وليست
  تنظيمية فحسب. كل وحدة هي وحدة يمكن أن تصبح خدمة.
- **`public.py`** هو العقد الكامل للوحدة. كل شيء آخر في الوحدة داخلي (الشرطة
  السفلية البادئة هي اصطلاح يفرضه الفرق باستخدام فحص الاستيراد import-linting).
  الوحدات الأخرى تستورد فقط من `public.py`.
- **كل وحدة تمتلك جداولها.** `invoicing` تمتلك جداول الفواتير؛ `payments` تمتلك
  جداول المدفوعات. لا وحدة تقرأ جداول أخرى مباشرة — البيانات عبر الوحدات تمر
  عبر الواجهة العامة. هذا ما يجعل قاعدة البيانات الواحدة آمنة *ويحافظ* على
  إمكانية الاستخراج، لأن بيانات الوحدة يمكن أن تنتقل معها.
- **بعد الاستخراج**، يصبح حد الوحدة حد خدمة: يحتفظ المونوليث بـ
  `reconciliation/public.py`، لكن تنفيذه يتغير من استدعاء داخل العملية إلى عميل
  HTTP. المستدعون لا يتغيرون، لأنهم كانوا يعتمدون فقط على الواجهة.

## التنفيذ

**الواجهة العامة للوحدة (`modules/payments/public.py`).** الواجهة الأمامية (facade)
هي الشيء الوحيد الذي قد تستخدمه الوحدات الأخرى. تعرض العمليات بمصطلحات المجال
وتخفي المستودع والنماذج والجداول خلفها.

```python
from dataclasses import dataclass
from decimal import Decimal
from app.modules.payments._repository import PaymentRepository


@dataclass(frozen=True)
class PaymentSummary:
    id: int
    amount: Decimal
    status: str


class PaymentsModule:
    """Public interface of the payments module. Other modules use ONLY this."""

    def __init__(self, repo: PaymentRepository) -> None:
        self._repo = repo

    async def get_summary(self, payment_id: int) -> PaymentSummary | None:
        payment = await self._repo.get(payment_id)
        if payment is None:
            return None
        return PaymentSummary(id=payment.id, amount=payment.amount, status=payment.status)
```

**عبور حد الوحدة بالطريقة الصحيحة.** عندما تحتاج invoicing إلى بيانات الدفع،
تستدعي واجهة payments الأمامية — فهي لا تستورد `payments._repository` أو تستعلم
جداول الدفع.

```python
# modules/invoicing/_service.py
from app.modules.payments.public import PaymentsModule  # the interface, not internals


class InvoiceService:
    def __init__(self, payments: PaymentsModule, repo: "InvoiceRepository") -> None:
        self._payments = payments
        self._repo = repo

    async def mark_paid(self, invoice_id: int, payment_id: int) -> None:
        summary = await self._payments.get_summary(payment_id)   # across the boundary
        if summary is None or summary.status != "succeeded":
            raise ValidationError("Payment is not settled.")
        invoice = await self._repo.get(invoice_id)
        invoice.status = "paid"
```

**فرض الحد.** الانضباط ليس كافيًا؛ يتم فحص القاعدة بواسطة أداة. عقد
import-linter يجعل الاستيراد عبر الحدود إلى التفاصيل الداخلية فشلًا في CI:

```ini
# importlinter.ini  — boundaries enforced in CI, not by hope
[importlinter]
root_package = app

[importlinter:contract:module-privacy]
name = Modules may only import each other's public interface
type = forbidden
source_modules =
    app.modules.invoicing
    app.modules.payments
    app.modules.reconciliation
forbidden_modules =
    app.modules.invoicing._repository
    app.modules.payments._repository
    app.modules.reconciliation._repository
```

**الاستخراج: يصبح الحد قفزة شبكية.** نظرًا لأن المستدعين يعتمدون فقط على
`reconciliation/public.py`، فإن استخراج الخدمة يعني تبديل تنفيذ الواجهة الأمامية
من استدعاء داخل العملية إلى عميل HTTP يستوفي الواجهة *نفسها*. وحدتا invoicing
وpayments لا تتغيران.

```python
# modules/reconciliation/public.py  — AFTER extraction, now an HTTP client
import httpx
from app.modules.reconciliation.contracts import ReconciliationReport


class ReconciliationModule:
    """Same interface as before; now backed by a remote service instead of
    an in-process handler. Callers are unaffected by the move."""

    def __init__(self, client: httpx.AsyncClient, base_url: str) -> None:
        self._client = client
        self._base_url = base_url

    async def run(self, account_id: int) -> ReconciliationReport:
        resp = await self._client.post(
            f"{self._base_url}/internal/reconcile", json={"account_id": account_id},
            timeout=30.0,   # the network can fail now — timeouts are mandatory
        )
        resp.raise_for_status()
        return ReconciliationReport(**resp.json())
```

**طوبولوجيا النشر (`deploy/docker-compose.yml`).** خدمتان، وبشكل حاسم — خدمة
reconciliation لها *قاعدة بيانات خاصة بها*. لا تتشارك قاعدة بيانات Invoicely.

```yaml
services:
  invoicely-api:
    build: ../services/invoicely-api
    environment:
      DATABASE_URL: postgresql+asyncpg://app@main-db/invoicely
      RECONCILIATION_URL: http://reconciliation-svc:8000
    depends_on: [main-db, reconciliation-svc]

  reconciliation-svc:
    build: ../services/reconciliation-svc
    deploy:
      replicas: 4            # scaled INDEPENDENTLY of the API — the whole point
    environment:
      DATABASE_URL: postgresql+asyncpg://recon@recon-db/reconciliation
    depends_on: [recon-db]

  main-db:
    image: postgres:16
  recon-db:                  # SEPARATE database — no shared data, no distributed monolith
    image: postgres:16
```

الاستخراج اشترى شيئًا واحدًا بالضبط — القدرة على تشغيل أربعة عمال reconciliation
دون مضاعفة التطبيق بأكمله أربع مرات — وكلف بالضبط ما يكلفه التوزيع دائمًا:
استدعاء شبكي يمكن أن يفشل الآن (ومن هنا المهلة الزمنية و`raise_for_status`)،
وقاعدة بيانات ثانية ونشر لتشغيله، واتساق eventual بين مخزني البيانات. تلك
المقايضة كانت تستحق العناء *لـ reconciliation* لأن قوة التوسع كانت حقيقية.
إجراء نفس المقايضة لـ invoicing أو notifications، اللتين لا تملكان مثل هذه
القوة، كان سيكون خسارة محضة. لاحظ ما *لم* يحدث: الخدمتان لا تتشاركان قاعدة
بيانات، والاستدعاء عملية واحدة coarse-grained، وليس ذهابًا وإيابًا ثرثارًا.
هذا الكبح هو الخط الفاصل بين الخدمات الصغرى والمونوليث الموزع.

## القرارات الهندسية

أربعة قرارات تحدد أين تهبط على الطيف وما إذا كانت الخطوة صحية.

### أين تبدأ؟

**الخيارات:** (1) مونوليث؛ (2) مونوليث معياري؛ (3) خدمات صغرى.

**المقايضات:** المونوليث هو الأقل عملًا ويمكن أن يتعفن دون انضباط. الخدمات
الصغرى أولاً تدفع كامل ضريبة الأنظمة الموزعة قبل أن يكون لديك التوسع أو
الفريق أو النضج التشغيلي للاستفادة — وفي حين أن المجال لا يزال يتغير، وهو
أسوأ وقت لتجميد الحدود في عقود شبكية. المونوليث المعياري يضيف فقط تكلفة
الانضباط الداخلي.

**التوصية:** ابدأ بمونوليث وفرض حدودًا معيارية مع نموه — أي مونوليث معياري. لا
تبدأ أبدًا بخدمات صغرى ما لم تكن مؤسسة كبيرة ذات فرق متعددة وعمليات ناضجة
ومجال تفهمه بالفعل. "MonolithFirst" لـ Fowler (قراءة إضافية) هي الملاحظة
التجريبية وراء هذا: تقريبًا كل نظام خدمات صغرى ناجح تم استخراجه من مونوليث،
وتقريبًا كل نظام خدمات صغرى أولاً عانى.

### كيف ترسم الحدود؟

**الخيارات:** (1) حسب الطبقة التقنية (خدمة "مصادقة"، خدمة "قاعدة بيانات")؛
(2) حسب القدرة التجارية / السياق المحدود (bounded context).

**المقايضات:** الحدود التقنية تنتج خدمات يجب لمسها جميعًا لأي ميزة والتي تثرثر
باستمرار عبر الشبكة — كرة الطين الكبيرة الموزعة. حدود القدرة (invoicing، payments،
reconciliation) تواءم كل وحدة أو خدمة مع شريحة متماسكة من العمل، مما يقلل الثرثرة
عبر الحدود، لكنها تتطلب فهمًا حقيقيًا للمجال لتكون صحيحة.

**التوصية:** ارسم الحدود حول القدرات التجارية / السياقات المحدودة (فكرة DDD من
الفصل 02)، وليس حول الطبقات التقنية. الحدود الجيدة هي اللعبة كلها: تحدد
الاقتران، والاقتران يحدد ما إذا كان الاستخراج تبديلًا (reconciliation في Invoicely)
أو إعادة كتابة.

### قاعدة بيانات مشتركة، أم قاعدة بيانات لكل وحدة؟

**الخيارات:** (1) جميع الوحدات/الخدمات تتشارك قاعدة بيانات واحدة وجداولها؛
(2) كل وحدة تمتلك بياناتها الخاصة.

**المقايضات:** في *مونوليث معياري*، قاعدة البيانات المشتركة الواحدة مقبولة —
وأبسط — *بشرط أن تمتلك كل وحدة جداولها* ولا تقرأ وحدة أخرى بياناتها مباشرة
(محرك مشترك، جداول خاصة؛ مخطط لكل وحدة schema-per-module يجعل هذا صريحًا).
في *الخدمات الصغرى*، مشاركة قاعدة البيانات على الإطلاق هي الخطيئة الكبرى: إنها
تعيد اقتران الخدمات إلى مونوليث موزع. قاعدة بيانات لكل خدمة تتيح الاستقلالية
لكنها تجبر على الاتساق eventual والاستعلامات عبر الخدمات من خلال APIs أو أحداث.

**التوصية:** مونوليث معياري — قاعدة بيانات واحدة، مالك جدول واحد لكل وحدة.
خدمات صغرى — قاعدة بيانات واحدة لكل خدمة، دون استثناءات، مع البيانات عبر
الخدمات من خلال استدعاءات API أو أحداث (الفصل 07). إذا لم تكن مستعدًا لتقسيم
البيانات، فأنت لست مستعدًا للخدمات الصغرى؛ ابقَ مونوليثًا معياريًا.

### متى تستخرج خدمة؟

**الخيارات:** (1) استخرج الوحدات إلى خدمات بشكل استباقي؛ (2) استخرج فقط عندما
تظهر قوة محددة.

**المقايضات:** الاستخراج الاستباقي يوزع قبل أن تعرف أن الحدود صحيحة ويدفع
الضريبة مبكرًا. الاستخراج القائم على القوة يحتفظ بالمونوليث حتى تظهر حاجة
ملموسة — توسع مستقل، إيقاع نشر مستقل، استقلالية الفريق، عزل الأخطاء — تبرر
ترقية وحدة واحدة، على حساب القيام بعمل الاستخراج تحت بعض الضغط.

**التوصية:** استخرج فقط عندما تتطلب قوة محددة ومسماة ذلك، واستخرج الوحدة التي
لديها القوة فقط — كما استخرجت Invoicely وحدة reconciliation للتوسع المستقل
وتركت كل شيء آخر في المونوليث. "الخدمات الصغرى أكثر حداثة" ليست قوة. اكتب
القوة والقرار في ADR
([`templates/adr.md`](../../templates/adr.md))؛ إذا لم تستطع تسمية القوة، لا تستخرج.

## المقايضات

كل نقطة على الطيف صحيحة في سياقات معينة وخاطئة في سياقات أخرى.

**المونوليث** هو أبسط شيء يعمل: بناء واحد، نشر واحد، إصدارات ذرية، معاملات
بسيطة، شيء واحد للمراقبة، وأسهل تطوير وتصحيح محلي. تتكلف مصاريفه مع التوسع —
يتوسع فقط ككل، يقيدك بمكدس واحد، يقرن نشر كل فريق معًا، ويتعفن ليصبح كرة
طين كبيرة دون انضباط داخلي. مناسب للمنتجات في مراحلها الأولى، والفرق الصغيرة،
والمجالات غير المثبتة؛ يصبح متوترًا بشكل متزايد مع نمو الفريق وقاعدة الكود.

**المونوليث المعياري** يحتفظ بكل البساطة التشغيلية للمونوليث مع إضافة حدود
داخلية مفروضة، مما يشتري قابلية الصيانة، وتوازي الفرق، وخيار استخراج الخدمات
لاحقًا. ثمنه هو الانضباط: الحدود ليست مفروضة بواسطة الشبكة، لذلك تتطلب واجهات
أمامية وفحص linting ومراجعة لتبقى، ولا يزال وحدة نشر وتوسع واحدة. مناسب
للأغلبية الكبيرة من المنتجات النامية — الافتراضي الذي يجادل هذا الفصل بأن معظم
الفرق يجب أن تجلس فيه لفترة أطول مما تظن.

**الخدمات الصغرى** تشتري النشر المستقل، والتوسع المستقل، واستقلالية الفريق،
وتنوع التكنولوجيا، وعزل الأخطاء. الفاتورة هي نظام موزع: الشبكة غير موثوقة
وبطيئة (سقطات الحوسبة الموزعة، في القراءة الإضافية)، لا توجد معاملات سهلة عبر
الخدمات (تحصل على الاتساق eventual والساغا)، كل خدمة تضاعف الحمل التشغيلي
(نشر، مراقبة، تسجيل، تتبع، تأمين، اكتشاف)، يصبح التطوير والاختبار المحليان
أصعب بكثير، وترتفع latency من النهاية إلى النهاية. مناسب للمؤسسات الكبيرة ذات
الفرق المستقلة المتعددة، والاحتياجات الحقيقية للتوسع المستقل، والنضج التشغيلي
لتشغيل الأنظمة الموزعة — وخاطئ، غالبًا بشكل مدمر، للفرق التي لا تملك تلك.

النقطة الفوقية: **يجب أن تكون "طويلًا بهذا القدر" لركوب الخدمات الصغرى.** يُقاس
الطول بعدد الفريق، والنضج التشغيلي، واستقرار المجال — وليس بالطموح. معظم الفرق
التي تسأل "هل يجب أن نستخدم خدمات صغرى؟" يجب أن تبني مونوليثًا معياريًا وتعيد
النظر عندما تظهر قوة محددة.

## الأخطاء الشائعة

**الخدمات الصغرى أولاً.** البدء بخدمات موزعة قبل أن يكون لديك التوسع أو
الفريق أو فهم المجال أو العمليات لدعمها — دفع كامل الضريبة مقدمًا مقابل فوائد
لا يمكنك استخدامها بعد. الإصلاح: ابدأ بمونوليث معياري؛ استخرج عندما تظهر قوة.

**المونوليث الموزع.** خدمات مقترنة جدًا لدرجة أنه يجب نشرها معًا — من خلال
قاعدة بيانات مشتركة، أو سلاسل استدعاء تزامنية ثرثارة، أو نماذج داخلية مشتركة
— فتحمل كل تكلفة التوزيع ولا شيء من استقلاليته. الإصلاح: كل خدمة تمتلك
بياناتها وتعرض API خشن (coarse)؛ إذا كان يجب نشر الخدمات معًا، فلا يجب أن
تكون خدمات منفصلة.

**مشاركة قاعدة بيانات عبر الخدمات.** الطريق الأكثر شيوعًا إلى المونوليث الموزع:
خدمتان تقرآن وتكتبان في نفس الجداول. الإصلاح: قاعدة بيانات لكل خدمة؛ البيانات
عبر الخدمات من خلال APIs أو أحداث (الفصل 07).

**حدود على المحور الخاطئ.** التقسيم حسب الاهتمام التقني (خدمة "مصادقة"، خدمة
"قاعدة بيانات إشعارات") بدلاً من القدرة التجارية، مما ينتج خدمات ثرثارة مقترنة
في النشر. الإصلاح: الحدود تتبع السياقات المحدودة والقدرات التجارية.

**السماح للمونوليث المعياري بالتعفن.** الإعلان عن الوحدات دون فرض حدودها، لذلك
تتراكم الاستيرادات عبرها حتى يصبح مونوليثًا عاديًا ويختفي خيار الاستخراج.
الإصلاح: فرض الحدود بواجهات أمامية وفحص import-linting في CI — الحدود التي لا
تفرضها لا توجد.

## أخطاء الذكاء الاصطناعي

تعلم المساعدون البنية المعمارية خلال دورة الضجيج حول الخدمات الصغرى، ويظهر
ذلك: **افتراضيهم هو الإفراط في التوزيع، وعندما يوزعون ينتجون مونوليثات موزعة.**
كلا الفشلتين يمنحانك تكاليف التوزيع دون فوائده. الإجراء المضاد هو جعل المونوليث
المعياري هو الافتراضي المعلن وفرض قواعد البيانات والحدود ميكانيكيًا، لأن
المساعد لن يحترمها بمفرده.

### Claude Code: الإفراط في التوزيع افتراضيًا

عندما يُطلب منه "تصميم البنية" أو إضافة قدرة كبيرة، يميل Claude Code إلى
اللجوء إلى خدمات منفصلة، ووسيطاء رسائل (message brokers)، و`docker-compose`
مليء بالمكونات — معيدًا إنتاج الشكل الثقيل بالخدمات الصغرى لبيانات تدريبه
لمشكلة يمكن لتطبيق واحد التعامل معها بشكل أفضل. إنه يصنع توزيعًا لم يطلبه
أحد.

**الكشف:** تصميم متعدد الخدمات، استدعاءات HTTP أو queue بين أشياء يمكن أن
تكون استدعاءات دوال، أو وسيط تم تقديمه لتطبيق صغير. إذا كان النظام المقترح
يحتوي على خدمات أكثر من عدد الأشخاص في الفريق، فاشتبه.

**الإصلاح:** ضع الافتراضي صراحةً:

> Default to a modular monolith — one deployable unit with enforced internal
> module boundaries. Do not propose separate services or a message broker unless I
> state a specific need for independent scaling or deployment, and if you do,
> justify the force.

### GPT: قاعدة البيانات المشتركة والمونوليث الموزع الثرثار

عندما تنتج نماذج عائلة GPT خدمات صغرى، فإنها بشكل روتيني تجعل الخدمات تتشارك
قاعدة البيانات، أو تستعلم جداول بعضها البعض، أو تجري سلاسل استدعاء تزامنية
دقيقة — منتجة مونوليثًا موزعًا. تبدو كخدمات صغرى وتتقترن كمونوليث.

**الكشف:** خدمات متعددة تشير إلى نفس `DATABASE_URL`، خدمة تقرأ جداول خدمة أخرى،
أو طلب واحد ينتشر في العديد من الاستدعاءات التزامنية بين الخدمات.

**الإصلاح:** اذكر قاعدة البيانات، وهي القاعدة المهمة:

> Each service must own its own database; no shared tables and no service querying
> another's database. Cross-service data goes through a coarse-grained API or
> events. Avoid chatty synchronous call chains between services.

### Cursor: إذابة حدود الوحدات من خلال طبقة البيانات

في مونوليث معياري، يميل Cursor إلى تلبية الحاجة لبيانات وحدة أخرى عن طريق
الاستعلام المباشر لجداول تلك الوحدة أو استيراد مستودعها الداخلي — لأن تلك
الرموز قابلة للوصول — بدلاً من المرور عبر الواجهة العامة للوحدة. كل اختصار
كهذا يقترن الوحدات على مستوى البيانات ويدمر بهدوء القدرة على استخراج أي منهما.

**الكشف:** استعلام في وحدة واحدة يقرأ أو ينضم إلى جداول وحدة أخرى، أو استيراد
لـ `_repository`/`_models` وحدة أخرى بدلاً من واجهتها `public`. الوصول إلى
الجداول عبر الوحدات هو البصمة.

**الإصلاح:** اشترط الواجهة وفرضها في الأدوات:

> Never read another module's tables or import its internals. Get the data through
> that module's public interface (`modules/<name>/public.py`). This is enforced by
> the import-linter contract in CI; keep it green.

## أفضل الممارسات

**ابدأ بمونوليث؛ نمِّ إلى مونوليث معياري.** اعتمد الخدمات الصغرى فقط عندما
تتطلب قوة محددة — توسع مستقل، إيقاع نشر مستقل، استقلالية الفريق، عزل الأخطاء
— ويمكنك تحمل العمليات. بالنسبة لمعظم المنتجات، المونوليث المعياري هو
الوجهة، وليس محطة عبور.

**ارسم الحدود حول القدرات التجارية.** تتبع الوحدات والخدمات السياقات المحدودة
(الفصل 02)، وليس الطبقات التقنية. الحدود الجيدة تقلل الثرثرة عبر الحدود وتجعل
الاستخراج اللاحق تبديلًا بدلاً من إعادة كتابة.

**امنح كل وحدة (وخدمة) ملكية فريدة لبياناتها.** في مونوليث معياري، مالك جدول
واحد لكل وحدة ولا وصول عبر الوحدات للجداول؛ في الخدمات الصغرى، قاعدة بيانات
واحدة لكل خدمة ولا مشاركة. تتدفق البيانات عبر الحدود من خلال واجهات أو
أحداث (الفصل 07). قاعدة البيانات المشتركة هي مونوليث موزع في طور التشكل.

**فرض الحدود ميكانيكيًا.** واجهات أمامية عامة بالإضافة إلى فحص import-linting
في CI بالإضافة إلى فصل المخطط — لأن الحد الذي يعتمد على الانضباط وحده سيتآكل،
والمساعد سيتآكله بشكل أسرع. برمج لواجهة الوحدة بحيث يمكن استخراج الوحدة دون
تغيير مستدعيها.

**اكتب قرارات الطوبولوجيا، واجعل الذكاء الاصطناعي افتراضيًا على مونوليث.** سجّل
قرارات الاستخراج وقواها كـ ADRs
([`templates/adr.md`](../../templates/adr.md))، واذكر "modular monolith, single
deployable unit" كافتراضي في `CLAUDE.md`
([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)) بحيث
يتوقف المساعدون عن اللجوء إلى خدمات لا تحتاجها.

## الأنماط المعاكسة (Anti-Patterns)

**الخدمات الصغرى أولاً (التوزيع المبكر).** التوزيع قبل أن يبرره التوسع أو
الفريق أو العمليات أو استقرار المجال — دفع كامل الضريبة مقابل فوائد غير قابلة
للاستخدام. العلامة: خدمات أكثر من المهندسين، واجتماعات يومية يهيمن عليها
البنية التحتية بدلاً من المنتج.

**المونوليث الموزع.** خدمات يجب نشرها معًا لأنها تتشارك قاعدة بيانات، أو
تتشارك نماذج، أو تثرثر تزامنيًا — كل تكلفة التوزيع، ولا شيء من الاستقلالية.
الربع الأسوأ على الطيف. العلامة: لا يمكنك نشر خدمة واحدة دون التنسيق مع
الخدمات الأخرى.

**قاعدة البيانات المشتركة.** خدمات متعددة تقرأ وتكتب في جداول مشتركة، تقترن
على مستوى البيانات تحت API. العلامة: `DATABASE_URL` واحد عبر الخدمات، أو هجرة
في خدمة تكسر أخرى.

**خدمات الكيان/CRUD.** خدمات مقسمة لكل كيان بيانات (خدمة "Customer" ليست سوى
CRUD على العملاء) بدلاً من لكل قدرة، مما ينتج استدعاءات تزامنية ثرثارة عبر
الخدمات لكل عملية حقيقية. العلامة: القيام بإجراء عمل واحد يتطلب استدعاءات
تزامنية لثلاث خدمات.

**المونوليث المعياري المتعفن.** وحدات مُعلنة بحدود غير مفروضة، لذلك تتراكم
الاستيرادات عبر الوحدات حتى تصبح كرة طين كبيرة عادية ويختفي خيار الاستخراج.
العلامة: ملفات `public.py` يتجاوزها الجميع، ولا يوجد import-linter في CI.

## شجرة القرار

"أي طوبولوجيا يجب أن يستخدمها هذا النظام، وهل يجب أن أقسم هذا الجزء؟"

```
Are you early-stage / small team / still learning the domain?
│
├── YES ──► MONOLITH. Keep it modular internally, but one deployable unit.
│           Do not distribute. Full stop.
│
└── NO (growing product, want maintainability + future options)
    │
    └──► MODULAR MONOLITH. Enforce module boundaries (facades, import-linting,
         one table-owner per module). This is the default for most products.
         │
         Is there a SPECIFIC force for a given module?
         (independent scaling · independent deploy cadence · team autonomy ·
          fault isolation)  — AND the ops maturity to run distributed systems?
         │
         ├── NO ──► Stay a modular monolith. "More modern" is not a force.
         │
         └── YES ──► Extract THAT module into a service (not all of them).
             │
             Is its boundary already clean? (public interface, owns its data,
             no other module reads its tables)
             │
             ├── NO ──► Fix the boundary first. You cannot cleanly extract a
             │          tangle; make it a proper module, then extract.
             │
             └── YES ─► Extract it: its own database, a coarse API or events,
                        timeouts on every call. Callers depend on the interface,
                        so they don't change. Record the force in an ADR.
```

## قائمة المراجعة

### قائمة مراجعة التنفيذ

- [ ] Each module exposes a public interface; internals are private and imported by no other module.
- [ ] Cross-module access goes through the public interface, never another module's tables or internals.
- [ ] Each module owns its tables; there is exactly one table-owner per module.
- [ ] Boundary rules are enforced in CI (import-linter or equivalent), not left to discipline.
- [ ] Any extracted service owns its own database and is called with explicit timeouts.
- [ ] Inter-service communication is coarse-grained (few, meaningful calls), not chatty.

### قائمة مراجعة البنية المعمارية

- [ ] Module/service boundaries follow business capabilities, not technical layers.
- [ ] The system is as far left on the spectrum as its actual needs allow (monolith → modular monolith → microservices).
- [ ] No two services share a database or tables.
- [ ] Every service extraction is justified by a named force, recorded in an ADR.
- [ ] Cross-boundary transactions are handled by eventual consistency / sagas, not distributed synchronous transactions.

### قائمة مراجعة الكود

- [ ] No new cross-module import of internals or cross-module table access (watch AI diffs).
- [ ] No shared-database or chatty-synchronous coupling introduced between services.
- [ ] New services/modules were justified, not added reflexively (guard against AI over-distribution).
- [ ] Remote calls have timeouts and handle partial failure.
- [ ] The change did not bypass a module's public interface.

### قائمة مراجعة النشر

- [ ] Each service has its own deploy pipeline, health check, and rollback path (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Each service's database has independent backups and migration process.
- [ ] Service-to-service calls degrade gracefully when a dependency is down (timeouts, fallbacks).
- [ ] Observability spans service boundaries (correlation IDs / distributed tracing), so a request can be followed across services.
- [ ] The number of deployable units matches the team's operational capacity to run them.

## التمارين

**1. عرّف وفرض حد وحدة.** خذ وحدات Invoicely وأعطِ واحدة منها (مثلاً،
`payments`) واجهة عامة مناسبة، مما يجعل مستودعها ونماذجها داخلية. ثم أضف عقد
import-linter يفشل CI إذا استوردت وحدة أخرى تفاصيلها الداخلية. الناتج هو
`public.py`، والتكوين، ولقط شاشة أو سجل للعقد يمسك انتهاكًا متعمدًا — دليل
على أن الحد مفروض وليس طموحًا.

**2. خطط لاستخراج كـ ADR.** اكتب ADR لاستخراج وحدة reconciliation إلى خدمة:
القوة المبررة له، والبيانات التي تمتلكها وكيف تنتقل، وآلية الاتصال (API تزامني
أم أحداث)، وأنماط الفشل الجديدة (المهلات الزمنية، الفشل الجزئي، الاتساق
eventual)، والتراجع. الناتج هو ADR
([`templates/adr.md`](../../templates/adr.md)) — النقطة هي أن كتابته بأمانة تكشف
أحيانًا أن القوة ليست قوية بما يكفي بعد.

**3. شخّص مونوليثًا موزعًا.** بالنظر إلى مجموعة من الخدمات حيث يتشارك بعضها
قاعدة بيانات وبعضها يقوم بسلاسل استدعاء تزامنية ثرثارة (ارسم واحدة، أو اطلب
من مساعد توليد تصميم "microservices" من موجه ساذج)، حدد كل نقطة اقتران خفي
وصف كيف ستصلح كل واحدة — افصل البيانات، واخشن APIs، أو ادمج الخدمات التي لم
يكن يجب تقسيمها. الناتج هو التشخيص المشروح.

## قراءة إضافية

- **Building Microservices, 2nd edition** (Sam Newman, O'Reilly) — العلاج الحاسم
  والمنعش، بما في ذلك مادة واسعة حول متى *لا* تستخدم الخدمات الصغرى ولماذا تبدأ
  بمونوليث. إذا قرأت كتابًا واحدًا في هذا الفصل، فهو هذا.
- **MonolithFirst** و **MicroservicePremium** (Martin Fowler, martinfowler.com) —
  مقالتان قصيرتان تقدمان القضية التجريبية للبدء بمونوليث ولمعاملة الخدمات الصغرى
  كقسط تدفعه فقط عندما يبرر التعقيد التوسع.
- **Modular Monoliths** (Simon Brown — محاضرة وكتابة) — أوضح حجة للوسط المُهمَل
  في الطيف، وإرشاد عملي حول فرض حدود الوحدات بحيث يبقى المونوليث معياريًا.
- **Fallacies of Distributed Computing** (Peter Deutsch, James Gosling, et al.) —
  الافتراضات الثمانية الخاطئة ("الشكة موثوقة"، "latency صفر"، "النطاق الترددي
  لا نهائي"، ...) التي تجعل الأنظمة الموزعة صعبة. اقرأ هذا قبل أن تقسم أي
  شيء؛ إنه جانب التكلفة من دفتر الخدمات الصغرى في صفحة واحدة.
