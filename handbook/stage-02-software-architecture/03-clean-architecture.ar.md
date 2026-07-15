# Clean Architecture

## Introduction

Clean Architecture هي طريقة لهيكلة التطبيق بحيث تعتمد قواعد عمله على لا شيء، ويعتمد كل شيء آخر عليها. أُطر العمل، وقاعدة البيانات، والويب، وواجهة المستخدم — كل الأشياء التي تتعامل معها معظم قواعد الشيفرة باعتبارها الأساس — تصبح *تفاصيل* تركَّب على خارج نواة نطاق مستقرة. قاعدتها الحاكمة الوحيدة، **قاعدة الاعتمادية (Dependency Rule)**، هي أن اعتماديات الشيفرة المصدرية تشير إلى الداخل فقط، نحو النطاق، ولا تشير أبدًا إلى الخارج نحو البنية التحتية.

تنتمي هذه إلى العائلة نفسها التي تضم Hexagonal Architecture (Ports and Adapters) وOnion Architecture؛ فهي تختلف في المفردات والمخططات لكنها تتشارك فكرة واحدة: قلب الاعتمادية المعتادة بحيث لا يعرف النطاق شيئًا عن قاعدة البيانات — بل تعرف قاعدة البيانات عن النطاق. وهي العكس المتعمَّد للبنية الطبقية في الفصل 01، حيث تتدفق الاعتمادية *لأسفل* نحو قاعدة البيانات. أما هنا فتتدفق *إلى الداخل* نحو قواعد العمل.

يأتي هذا الفصل مصحوبًا بتحذير مكتوب في دستور Handbook: **لا تلجأ إلى Clean Architecture في كل مشروع.** إنها تشتري خصائص حقيقية ذات قيمة — نطاقًا مستقلًا عن أُطر العمل وقابلًا للاختبار — بتكلفة حقيقية وكبيرة في عدم المباشرة والطقوس. ومعظم التطبيقات ذات الطابع CRUD، هذه التكلفة تفوق الفائدة بكثير، ويكون التنظيم الطبقي أو القائم على الميزات هو الإجابة الصحيحة. وعليه فإن مهارة الهندسة التي يعلِّمها هذا الفصل ذات وجهين: كيف تبنيها *وكيف* تعرف متى لا تستخدمها. سنطبِّقها على الجزء الوحيد من Invoicely الذي يستحقها — وهو محرك التسوية (reconciliation engine) — ونرفضها صراحةً في الأجزاء التي لا تستحقها.

## Why It Matters

تأمَّل فيما ترتبط به البنية الطبقية. في الفصل 01، كانت طبقة الخدمة تعتمد على المستودع (Repository)، الذي كان يعتمد بدوره على SQLAlchemy وPostgreSQL. تتدفق سلسلة الاعتمادية من منطق عملك *لأسفل* إلى البنية التحتية — فقواعد عملك تستورد مكتبة قاعدة بياناتك وتتأثر بشكلها. غيِّر منهجية الاستمرارية (persistence) وتنتشر التموجات إلى الأعلى؛ واختبر قاعدة عمل فتجرُّ معها قاعدة بيانات؛ يندمج النطاق والإطار معًا في كتلة واحدة.

بالنسبة لمعظم التطبيقات، هذا الاندماج مقبول — فالتطبيق *هو* في معظمه CRUD فوق قاعدة بيانات، والتظاهر بخلاف ذلك هو هندسة مفرطة. لكن بعض التطبيقات تمتلك نواة حقيقية من منطق العمل معقدة وقيِّمة — من النوع الذي يُبرِّر وجود الشركة — وبالنسبة لهذه النواة يكون الاقتران عبئًا:

- **المنطق القيِّم يعمِّر أطول من بنيته التحتية.** خوارزمية المطابقة في Invoicely هي ما يميِّزها؛ يجب أن تكون قابلة للتعبير والاختبار دون إشارة إلى أي قاعدة بيانات أو إطار ويب يصادف أنه تحتها هذه السنة.
- **المنطق المعقد يحتاج اختبارًا معزولًا.** قواعد العمل ذات الفروع والثوابت الكثيرة هي بالضبط ما تريد اختباره بشكل شامل — ولا تستطيع ذلك بتكلفة منخفضة إذا كان كل اختبار يحتاج قاعدة بيانات. النطاق المستقل عن أُطر العمل قابل للاختبار السريع بالبناء.
- **البنية التحتية هي حقًا مجرد تفصيل بالنسبة لهذه النواة.** سواء قرأت التسوية من Postgres، أو من طابور، أو من مُحاكاة في اختبار، فإن ذلك غير مهم *لكيفية عمل المطابقة*. تجعل Clean Architecture هذا اللا-أهمية هيكلًا بنيويًا.

البُعد الخاص بالذكاء الاصطناعي دقيق ومحدد هنا. سينتج المساعد عن طيب خاطر شيفرة *تبدو* وكأنها Clean Architecture — المجلدات، والواجهات، والأسماء — بينما ينتهك بصمت قاعدة الاعتمادية، لأن السحب الطبيعي للتوليد هو نحو الشيء الملموس في اليد (نموذج ORM، نوع الإطار) لا نحو التجريد. "يبدو نظيفًا" و"يطيع قاعدة الاعتمادية" ادعائان مختلفان، والثاني فقط هو الذي يستحق شيئًا.

## Mental Model

البنية بأكملها قاعدة واحدة حول اتجاه الاعتمادية:

```
   LAYERED (Ch 01): dependencies point DOWN, toward the database

     Service ──► Repository ──► SQLAlchemy ──► PostgreSQL
     (your business rules depend on your infrastructure)


   CLEAN: dependencies point IN, toward the domain

     ┌───────────────────────────────────────────────────┐
     │  FRAMEWORKS & DRIVERS   (FastAPI, SQLAlchemy, PG)   │
     │   ┌─────────────────────────────────────────────┐  │
     │   │  INTERFACE ADAPTERS  (controllers, repos)     │  │
     │   │   ┌─────────────────────────────────────┐    │  │
     │   │   │  APPLICATION  (use cases + PORTS)     │    │  │
     │   │   │    ┌─────────────────────────────┐    │    │  │
     │   │   │    │  DOMAIN (entities + rules)    │    │    │  │
     │   │   │    │  pure Python, knows nothing   │    │    │  │
     │   │   │    └─────────────────────────────┘    │    │  │
     │   │   └─────────────────────────────────────┘    │  │
     │   └─────────────────────────────────────────────┘  │
     └───────────────────────────────────────────────────┘

     Dependencies point INWARD only. The domain knows nothing.
     The database depends on the domain's interface, not vice versa.
```

الآلية التي تجعل الاعتمادية للداخل فقط ممكنة هي **عكس الاعتمادية (dependency inversion)**، وتستحق الرؤية بشكل ملموس لأنها الحركة الوحيدة الحقيقية غير البديهية:

```
   The use case needs to load payments. But it must not depend on the database.
   So:

   1. The APPLICATION layer defines a PORT — an interface describing what it
      needs:   "give me the unreconciled payments for an account."
   2. The use case depends only on that port (an abstraction it owns).
   3. An ADAPTER in the outer layer IMPLEMENTS the port using SQLAlchemy.

   Result: the arrow is inverted. The SQLAlchemy adapter depends on the
   application's port. The application depends on nothing outward. The database
   is now a plugin to the domain.
```

نتيجتان تحددان الانضباط:

**الطبقة الداخلية هي التي تملك الواجهة؛ والطبقة الخارجية هي التي تنفِّذها.** الـ port (وهو `PaymentRepository`) يُعرَّف *مع حالة الاستخدام*، لا مع شيفرة قاعدة البيانات. هذا ما يُوجِّه الاعتمادية إلى الداخل. إذا كانت الواجهة تعيش في طبقة المحوِّلات (adapters)، فلديك بنية طبقية بكلمات إضافية، والاعتمادية لا تزال تشير إلى الخارج.

**النواة لا تتكلم إلا بلغة Python خالصة.** كيانات النطاق (Domain entities) هي dataclasses، لا نماذج ORM؛ حالات الاستخدام تأخذ وتُرجع أنواع النطاق، لا `Request` ولا Pydantic ولا `Session`. اللحظة التي يظهر فيها نوع إطار في تواقيع النواة، تتوقف النواة عن كونها مستقلة عن الإطار وتفشل البنية بصمت.

تعريف عملي:

> **Clean Architecture تعكس الاعتمادية بحيث لا تعتمد قواعد العمل على شيء، وتعتمد البنية التحتية عليها. قيمتها نواتج نطاق مستقلة عن أُطر العمل وقابلة للاختبار المعزول — وتكلفتها قدر من عدم المباشرة يبرِّرها فقط كون هذه النواة معقدة وقيِّمة.**

## Production Example

**محرك التسوية في Invoicely** هو المكان الصحيح — والوحيد — في التطبيق لتطبيق هذا. إنه ما يميِّز المنتج (المرحلة 1، الفصلان 02 و06)، ومنطق المطابقة فيه معقد حقًا (مبالغ غير دقيقة، تسجيل ثقة، مدفوعات جزئية)، وهو الشيفرة التي يحتاج الفريق إلى اختبارها بشكل شامل وحمايتها من تذبذب البنية التحتية. كل ما تُحسِنه Clean Architecture، تحتاجه التسوية.

بقية Invoicely لا تحتاجها. إنشاء فاتورة، تحرير عميل، صفحة الإعدادات — هذه CRUD فوق قاعدة بيانات، وتغليفها بكيانات ومنافذ ومحولات ومُحوِّلات (mappers) سيكون طقسًا محضًا (تحذير الفصل المركزي، والإفراط في الهندسة في المرحلة 1، الفصل 07). لذا نطبِّق Clean Architecture على وحدة التسوية ونترك ميزة الفواتير كما هي من الفصل 02: مجلد ميزة بطبقات. قاعدة الشيفرة الحقيقية مسموح لها — بل ينبغي لها — أن تستخدم بنى مختلفة للأجزاء ذات الاحتياجات المختلفة.

سنبني حالة استخدام "تشغيل التسوية" بنطاق نقي، وport، ومحول SQLAlchemy، ثم — وهذه هي الفائدة المرجوة — اختبارًا يمارس حالة الاستخدام كاملةً دون أي قاعدة بيانات.

## Folder Structure

```
features/reconciliation/
├── domain/                      # INNERMOST — pure business rules, no imports out
│   ├── entities.py              #   Payment, Invoice, Match — plain dataclasses
│   └── matching.py              #   the matching algorithm (the differentiator)
│
├── application/                 # USE CASES + PORTS (interfaces the core owns)
│   ├── ports.py                 #   PaymentRepository, InvoiceRepository (Protocols)
│   └── run_reconciliation.py    #   the use case, depends only on ports
│
├── adapters/                    # OUTER — implement ports, map to infrastructure
│   ├── sqlalchemy_repos.py      #   concrete repos; map ORM <-> domain entities
│   └── api.py                   #   FastAPI controller; wires adapters into the use case
│
└── tests/
    └── test_run_reconciliation.py  # exercises the use case with in-memory fakes
```

لماذا هذا الشكل:

- **`domain/`** هو المركز ولا يستورد شيئًا من الطبقات حوله — لا من طبقة التطبيق، ولا من المحولات، وقبل كل شيء لا من SQLAlchemy ولا من FastAPI. إذا بحثت (`grep`) في هذا المجلد عن `sqlalchemy` أو `fastapi` وظهرت نتيجة، فالبنية مكسورة.
- **`application/`** يحتوي حالات الاستخدام، والأهم أنه يحتوي الـ *ports* التي تعتمد عليها. الـ port يعيش هنا — مع الشيفرة التي تحتاجه — لا في `adapters/`. هذا الموضع هو ما يعكس الاعتمادية.
- **`adapters/`** هو حيث تعيش البنية التحتية: المستودعات الخرسانية (concrete repositories) التي تنفِّذ المنافذ باستخدام SQLAlchemy وتُحوِّل بين صفوف ORM وكيانات النطاق، ووحدة تحكم FastAPI التي تُجمِّع حالة الاستخدام وتستدعيها. المحولات تعتمد إلى الداخل (على المنافذ والنطاق)؛ ولا يوجد شيء في الداخل يعتمد عليها.
- **`tests/`** يمكنه اختبار حالة الاستخدام مباشرة بتوفير تطبيقات داخل الذاكرة (in-memory) للمنافذ — لا قاعدة بيانات، لا HTTP. هذه القدرة هي العائد على الاستثمار كله.

## Implementation

**النطاق (`domain/entities.py`) — Python خالصة، بلا إطار.** هذه ليست نماذج ORM. إنها مفاهيم العمل، مُعبَّر عنها في dataclasses خالصة يمكنها العمل دون تثبيت قاعدة بيانات.

```python
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Payment:
    id: int
    account_id: int
    amount: Decimal
    reference: str


@dataclass(frozen=True)
class Invoice:
    id: int
    account_id: int
    amount: Decimal
    customer_name: str


@dataclass(frozen=True)
class Match:
    invoice_id: int
    payment_id: int
    confidence: float
```

**المنافذ (`application/ports.py`) — واجهات تملكها النواة.** أصناف `Protocol` في Python تَصِف *ما تحتاجه حالة الاستخدام* دون ذكر أي تطبيق. هذا هو التجريد الذي تشير إليه الاعتمادية.

```python
from typing import Protocol
from app.features.reconciliation.domain.entities import Invoice, Payment


class PaymentRepository(Protocol):
    async def unreconciled_for_account(self, account_id: int) -> list[Payment]: ...
    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None: ...


class InvoiceRepository(Protocol):
    async def open_for_account(self, account_id: int) -> list[Invoice]: ...
```

**حالة الاستخدام (`application/run_reconciliation.py`) — تعتمد فقط على المنافذ.** لاحظ الواردات (imports): النطاق والمنافذ، ولا شيء غير ذلك. لا توجد SQLAlchemy هنا، ولا FastAPI، ولا مستودع خرساني. هذه الشيفرة لا تستطيع رؤية البنية التحتية.

```python
from dataclasses import dataclass
from app.features.reconciliation.application.ports import (
    InvoiceRepository,
    PaymentRepository,
)
from app.features.reconciliation.domain.entities import Match
from app.features.reconciliation.domain.matching import match_payments_to_invoices


@dataclass
class ReconciliationReport:
    matched: int
    needs_review: list[Match]


class RunReconciliation:
    def __init__(
        self, payments: PaymentRepository, invoices: InvoiceRepository
    ) -> None:
        self._payments = payments
        self._invoices = invoices

    async def execute(self, account_id: int) -> ReconciliationReport:
        payments = await self._payments.unreconciled_for_account(account_id)
        invoices = await self._invoices.open_for_account(account_id)

        matches = match_payments_to_invoices(payments, invoices)
        confident = [m for m in matches if m.confidence >= 0.9]
        for m in confident:
            await self._payments.mark_reconciled(m.payment_id, m.invoice_id)

        return ReconciliationReport(
            matched=len(confident),
            needs_review=[m for m in matches if 0.5 <= m.confidence < 0.9],
        )
```

**المحوِّل (`adapters/sqlalchemy_repos.py`) — ينفِّذ المنفذ، ويُحوِّل بين ORM والنطاق.** هذا هو المكان الذي يُسمح فيه بوجود SQLAlchemy. ينفِّذ المنفذ بشكل هيكلي (لا حاجة إلى وراثة صريحة، بفضل `Protocol`) ويُترجم بين صفوف قاعدة البيانات وكيانات النطاق.

```python
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from app.features.reconciliation.domain.entities import Payment
from app.models.payment import PaymentORM


class SqlAlchemyPaymentRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def unreconciled_for_account(self, account_id: int) -> list[Payment]:
        rows = await self._session.scalars(
            select(PaymentORM).where(
                PaymentORM.account_id == account_id,
                PaymentORM.reconciled_at.is_(None),
            )
        )
        return [
            Payment(id=r.id, account_id=r.account_id, amount=r.amount, reference=r.reference)
            for r in rows
        ]

    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None:
        await self._session.execute(
            update(PaymentORM)
            .where(PaymentORM.id == payment_id)
            .values(reconciled_at=func.now(), matched_invoice_id=invoice_id)
        )
```

**وحدة التحكم (`adapters/api.py`) — تربط البنية التحتية بحالة الاستخدام.** يعيش FastAPI هنا في الخارج. تبني المحولات، وتحقنها في حالة الاستخدام، وتُترجم نتيجة النطاق إلى استجابة HTTP — وهو المكان الوحيد الذي تلتقي فيه العوالم الثلاثة.

```python
from fastapi import APIRouter
from app.core.auth import CurrentAccountDep
from app.core.db import SessionDep
from app.features.reconciliation.adapters.sqlalchemy_repos import (
    SqlAlchemyInvoiceRepository,
    SqlAlchemyPaymentRepository,
)
from app.features.reconciliation.application.run_reconciliation import RunReconciliation

router = APIRouter(prefix="/reconciliation", tags=["reconciliation"])


@router.post("/run")
async def run(session: SessionDep, account: CurrentAccountDep) -> dict:
    use_case = RunReconciliation(
        payments=SqlAlchemyPaymentRepository(session),
        invoices=SqlAlchemyInvoiceRepository(session),
    )
    report = await use_case.execute(account.id)
    await session.commit()
    return {"matched": report.matched, "needs_review": len(report.needs_review)}
```

**العائد المرجو (`tests/test_run_reconciliation.py`) — حالة الاستخدام كاملة، بلا قاعدة بيانات.** لأن حالة الاستخدام تعتمد فقط على المنافذ، يقدم الاختبار مُحاكيات داخل الذاكرة (in-memory fakes) ويُمارس منطق المطابقة الحقيقي بأقصى سرعة.

```python
from decimal import Decimal
from app.features.reconciliation.application.run_reconciliation import RunReconciliation
from app.features.reconciliation.domain.entities import Invoice, Payment


class InMemoryPayments:
    def __init__(self, payments: list[Payment]) -> None:
        self._payments = payments
        self.reconciled: list[tuple[int, int]] = []

    async def unreconciled_for_account(self, account_id: int) -> list[Payment]:
        return [p for p in self._payments if p.account_id == account_id]

    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None:
        self.reconciled.append((payment_id, invoice_id))


class InMemoryInvoices:
    def __init__(self, invoices: list[Invoice]) -> None:
        self._invoices = invoices

    async def open_for_account(self, account_id: int) -> list[Invoice]:
        return [i for i in self._invoices if i.account_id == account_id]


async def test_confident_match_is_reconciled() -> None:
    payments = InMemoryPayments([Payment(1, 42, Decimal("100.00"), "INV-1")])
    invoices = InMemoryInvoices([Invoice(9, 42, Decimal("100.00"), "Acme")])

    report = await RunReconciliation(payments, invoices).execute(account_id=42)

    assert report.matched == 1
    assert invoices  # unchanged
    assert payments.reconciled == [(1, 9)]
```

هذا الاختبار يعمل في ميكروثوانٍ، ولا يحتاج PostgreSQL، ويُمارس منطق العمل الفعلي. إعادة إنتاج هذا القدر من الثقة لقواعد تسوية معقدة في البنية الطبقية بالفصل 01 كان سيتطلب fixture قاعدة بيانات لكل حالة — وهو بالضبط الاحتكاك الذي يجعل المنطق المعقد غير مختبر بشكل كافٍ في الواقع. *هذا* هو ما اشترته لنا عدم المباشرة. إذا كانت ميزة ما لن تستفيد من هذا النوع من الاختبارات، فهي لا تحتاج هذه البنية.

## Engineering Decisions

أربعة قرارات تحكم Clean Architecture، والأول هو الأهم بفارق كبير.

### Does this part of the system warrant Clean Architecture at all?

**الخيارات:** (1) تطبيقها على التطبيق بأكمله؛ (2) تطبيقها فقط على نواة النطاق المعقدة والقيِّمة؛ (3) عدم استخدامها.

**المقايضات:** تطبيقها في كل مكان يفرض كيانات ومنافذ ومحولات ومُحوِّلات على CRUD لا تحوي قواعد عمل تستحق الحماية — طقوس هائلة بلا فائدة، وأكثر الطرق شيوعًا لإساءة استخدام هذه البنية. تطبيقها على النواة فقط يُركِّز التكلفة حيث يوجد العائد. عدم استخدامها إطلاقًا هو الصحيح للتطبيقات البسيطة حقًا.

**التوصية:** طبِّقها جراحيًا على النواة المعقدة فقط، ولا شيء غيرها — التسوية تحصل عليها، الفواتير لا. قاعدة الدستور ليست مجرد اقتراح: Clean Architecture على CRUD هندسة مفرطة، وقاعدة الشيفرة التي تستخدمها بشكل موحَّد تكون في الغالب قد طبَّقتها حيث لا تستحق. قرِّر لكل وحدة على حدة، باستخدام اختبار "هل الاختبارات المعزولة والاستقلال عن الإطار ستساعدان فعلًا هنا؟".

### Where do the ports live?

**الخيارات:** (1) تعريف واجهة المنفذ في طبقة التطبيق/النطاق؛ (2) تعريفها في طبقة المحولات/البنية التحتية.

**المقايضات:** البنية بأكملها تعتمد على هذا. منفذ مُعرَّف مع حالة الاستخدام (الخيار 1) يُوجِّه الاعتمادية إلى الداخل — المحول يعتمد على النواة. منفذ مُعرَّف في طبقة المحولات (الخيار 2) يترك الاعتمادية تشير إلى الخارج ويعطيك طبقية عادية بثوب من مفردات الواجهات.

**التوصية:** الطبقة الداخلية هي التي تملك المنفذ، دائمًا. هذا جوهر عكس الاعتمادية، وأكثر ما يُخطَأ فيه، حتى من قِبل الذكاء الاصطناعي. حالة الاستخدام تُعلن ما تحتاجه؛ والبنية التحتية تتوافق معه.

### Separate domain entities from ORM models?

**الخيارات:** (1) استخدام نماذج ORM ككيانات نطاق؛ (2) إبقاء كيانات نطاق خالصة والتحويل من/إلى ORM في المحول.

**المقايضات:** إعادة استخدام نماذج ORM شيفرة أقل، وتقرن النطاق بـ SQLAlchemy فورًا — وهو ما يُبطل الغرض الكامل بينما لا يزال يبدو Clean Architecture. الكيانات المنفصلة تكلِّف طبقة ترجمة (المحول يترجم الصفوف إلى dataclasses وبالعكس) لكنها تُبقي النواة خالية فعلًا من أُطر العمل وقابلة للاختبار دون قاعدة بيانات.

**التوصية:** افصل بينها — نموذج ORM بوصفه كيان نطاق ليس Clean Architecture، بل بنية طبقية باسم مجلد مضلِّل. تكلفة الترجمة هي ثمن الدخول؛ إذا كنت غير مستعد لدفعها، فأنت لم تكن بحاجة إلى هذه البنية، وعليك استخدام مقاربة الفصل 01 بصدق.

### How many layers, and how strict?

**الخيارات:** (1) دوائر Clean الأربع الكاملة مع مقدِّمي عرض (presenters) ومُحوِّلات و DTO لكل طبقة؛ (2) نواة سداسية (hexagonal) ثلاثية الأجزاء عملية (نطاق، حالات استخدام + منافذ، محولات).

**المقايضات:** الطقوس الكاملة مخلصة للمخططات، وكثيرًا ما تكون بنية أكثر مما يحتاجه تطبيق ويب، مع ترجمة DTO ثلاث مرات في الدخول والخروج. النسخة السداسية العملية تحتفظ بالعكس الجوهري (ports و adapters) دون تكاثر مقدِّمي العرض وDTO.

**التوصية:** النواة السداسية العملية لمعظم التطبيقات التي تحتاج هذا أصلًا — النطاق، حالات الاستخدام مع المنافذ، والمحولات. أَضف بنية أكثر فقط إذا اقتضى ذلك ألم ملموس (مثلًا وجود آليات تسليم متعددة ومختلفة جدًا). الهدف هو قاعدة الاعتمادية، لا عدد المربعات في المخطط.

## Trade-offs

تشتري Clean Architecture خصائص حقيقية قيِّمة بتكلفة حقيقية وكبيرة، ولا يتأرجح الميزان لصالحها إلا لأقلية من الشيفرة.

**عدم المباشرة حقيقية ودائمة.** المنافذ والمحولات والمُحوِّلات وفصل كيانات النطاق عن نماذج ORM تعني مزيدًا من الملفات والأنواع والقفزات لكل تغيير. إضافة حقل واحد قد تمس الكيان، ونموذج ORM، والمُحوِّل، وربما المنفذ. بالنسبة لشيفرة بلا قواعد معقدة تستحق الحماية، هذا عبء ميت — تعقيد عرضي من المرحلة 1 الفصل 07، مفروض بالبنية.

**فائدة "تبديل قاعدة البيانات" وهم في الغالب.** كثيرًا ما يُبرَّر اللجوء إلى Clean Architecture بعبارة "يمكننا التبديل من Postgres إلى MongoDB دون لمس النطاق." لن تفعل ذلك تقريبًا أبدًا، والبناء لمستقبل متخيَّل هو تعميم تخميني (الفصل 07). لا تبرِّر البنية بقدرة تبديل قواعد البيانات — برِّرها إن كانت تستحق، باختبار المنطق وحماية نطاق معقد، وهما فائدتان تجمعهما فعلًا.

**لها منحنى تعلُّم حاد ويسهل تزييفها.** الفرق الجديدة عليها تنتج شيفرة تمتلك المجلدات وأسماء الواجهات لكنها تنتهك قاعدة الاعتمادية — نماذج ORM ككيانات، منافذ في الطبقة الخطأ، أنواع أُطر في النواة. البنية لا تقدِّم قيمة ما لم تُطَاع القاعدة فعلًا، وطاعتها تتطلب فهم *لماذا* تشير الأسهم إلى الداخل، لا مجرد نسخ المخطط.

**متى تستخدمها ومتى لا.** استخدمها لنواة نطاق معقدة وقيِّمة وطويلة العمر تحتاج إلى اختبارها بشكل شامل بمعزل عنها وحمايتها من تذبذب البنية التحتية — التسوية في Invoicely، ومحرك تسعير، ومحرك قواعد، ونموذج مخاطرة. ولا تستخدمها لتطبيقات CRUD، والنطاقات البسيطة، والمشاريع قصيرة العمر، والفرق الصغيرة التي لا تملك شهية للطقوس — أي معظم البرمجيات. عند الشك، ابدأ بالطبقية أو القائمة على الميزات (الفصلان 01–02) واستخرج نواة نظيفة لاحقًا *إذا* برز نطاق معقد حقًا؛ فإن تركيب النواة لاحقًا أرخص من حمل الطقوس في كل مكان منذ اليوم الأول.

## Common Mistakes

**تطبيقها على كل شيء.** تغليف CRUD بسيط بكل المعدات الكاملة من كيانات ومنافذ ومحولات ومُحوِّلات، وإغراق ميزات تافهة بالطقوس. الإصلاح: طبِّق Clean Architecture فقط على نواة النطاق المعقدة؛ واستخدم بنى أبسط في بقية قاعدة الشيفرة.

**نماذج ORM ككيانات نطاق.** استخدام نماذج SQLAlchemy باعتبارها "الكيانات"، مما يجعل النطاق يستورد ORM ويُفقد الاستقلال عن الإطار — وهو كل المغزى — بينما لا تزال المجلدات تقول `domain/`. الإصلاح: كيانات النطاق هي dataclasses خالصة؛ المحول يُحوِّل صفوف ORM إليها.

**منافذ في الطبقة الخطأ.** تعريف واجهة المستودع في طبقة المحولات، تاركةً الاعتمادية تشير إلى الخارج. الإصلاح: المنفذ يعيش مع حالة الاستخدام التي تحتاجه؛ والمحول ينفِّذه. مكان الواجهة *هو* البنية.

**أنواع أُطر في النواة.** تمرير `Request`، أو نماذج Pydantic، أو `Session` الخاصة بـ SQLAlchemy إلى حالات الاستخدام أو شيفرة النطاق، مما يلوِّث المركز الخالي من أُطر العمل. الإصلاح: حوِّل إلى أنواع نطاق عند الحد (boundary)؛ تواقيع النواة لا تذكر إلا Python خالصة.

**حالات استخدام فقيرة (Anemic use cases).** حالات استخدام تكتفي بإعادة التوجيه إلى مستودع دون أي منطق نطاق — كل طقوس Clean Architecture بلا جوهر، ما يعني أن النطاق لم يكن يستحقها. الإصلاح: إذا كانت حالات الاستخدام مجرد إعادة توجيه صِرف، فقد أثبتَّ أن هذه الوحدة CRUD؛ أَلغِ البنية واستخدم مقاربة الفصل 01.

## AI Mistakes

كل فشل هنا هو الفشل نفسه: **المساعد ينتج شيفرة تبدو Clean Architecture لكنها تنتهك قاعدة الاعتمادية**، لأن الاتجاه الطبيعي للتوليد هو نحو الكائن الملموس في اليد — نموذج ORM، نوع الإطار، المستودع الحقيقي — لا نحو التجريد الذي تطلبه القاعدة. الإجراء المضاد هو المراجعة الصريحة لـ*اتجاه* الاعتمادية، وعدم الوثوق مطلقًا بأن أسماء المجلدات الصحيحة تعني أسهمًا صحيحة.

### Claude Code: dependencies pointing the wrong way

عند طلب تنفيذ حالة استخدام، كثيرًا ما يستورد Claude Code مستودع SQLAlchemy الخرساني مباشرةً في حالة الاستخدام، أو يستدعي قاعدة البيانات من داخل شيفرة النطاق — لأن الربط بالشيء الحقيقي هو المسار الأقل مقاومة، وعكس اعتمادية عبر منفذ حركة متعمَّدة وغير بديهية. النتيجة تعمل وتبدو مهيكلة بينما النواة مقترنة مباشرة بالبنية التحتية.

**اكتشاف:** أي استيراد لمحول، أو SQLAlchemy، أو مستودع خرساني داخل `domain/` أو `application/`. ابحث (`grep`) في الطبقات الداخلية عن `sqlalchemy`/`adapters` — أي نتيجة هي انتهاك.

**الإصلاح:** اذكر القاعدة والآلية:

> The use case must depend only on a port (a Protocol) defined in the application
> layer, never on a concrete repository or SQLAlchemy. Define the interface with
> the use case; implement it in an adapter. Dependencies point inward only.

### GPT: the ORM model masquerading as the domain entity

نماذج عائلة GPT كثيرًا ما تجعل "الكيان" نموذجًا لـ SQLAlchemy (أو Pydantic) وتبني حالة الاستخدام حوله — فتنشئ شيئًا به مجلدات `domain/` و`use_cases/` و`ports/` لكن نواته ملحومة بـ ORM. يبدو نظيفًا ويكسر القاعدة الوحيدة المهمة بصمت.

**اكتشاف:** "كيان" النطاق هو نموذج SQLAlchemy أو Pydantic؛ حالات الاستخدام تتلاعب بكائنات ORM؛ ولا توجد خطوة ترجمة في المحول.

**الإصلاح:** اشترط الفصل صراحةً:

> Domain entities must be plain dataclasses with no SQLAlchemy or Pydantic base.
> The adapter maps between ORM rows and domain entities. The use case must never
> touch an ORM object.

### Cursor: leaking framework types inward

عند التعديل في محول أو وحدة تحكم والوصول إلى حالة الاستخدام، يميل Cursor إلى تمرير أي كائن في اليد عبر الحد — الـ `Request` الخاص بـ FastAPI، أو نموذج جسم Pydantic، أو الـ `Session` — إلى تواقيع حالة الاستخدام أو النطاق، لأن هذه هي الرموز المتاحة في موقع الاستدعاء. كل تسرُّب يُلوِّث النواة الخالية من أُطر العمل.

**اكتشاف:** أنواع أُطر العمل (`Request`، `AsyncSession`، نماذج Pydantic) تظهر في معاملات أو أنواع إرجاع حالات الاستخدام أو دوال النطاق. تواقيع النواة يجب أن تذكر Python خالصة وأنواع نطاق فقط.

**الإصلاح:** حوِّل عند الحد، وحافظ على نظافة النواة:

> The controller converts framework objects into domain types before calling the
> use case. Do not pass `Request`, `Session`, or Pydantic models into the
> application or domain layer — those layers see only domain entities and plain
> values.

## Best Practices

**طبِّقها على النواة المعقدة فقط.** حدِّد الجزء الصغير من النظام الذي يحوي قواعد عمل معقدة وقيِّمة فعلًا، وأَعطِ *هذا الجزء* معاملة Clean Architecture؛ واترك CRUD كما هو طبقيًا أو قائمًا على الميزات. قاعدة الشيفرة ذات البنى المختلطة، المطابقة لاحتياجات كل جزء، علامة على الحكم السليم، لا على التناقض.

**حافظ على نقاء Python في النطاق.** الكيانات هي dataclasses؛ ولا يستورد النطاق إطارًا ولا بنية تحتية. الاختبار ميكانيكي: الطبقات الداخلية لا تحوي `import sqlalchemy` ولا `import fastapi`.

**دع الطبقة الداخلية تملك الواجهات.** تُعرَّف المنافذ مع حالات الاستخدام التي تعتمد عليها؛ وتنفيذها في المحولات من الخارج. هذا الموضع هو ما يعكس الاعتمادية — أخطِئه فيكون لديك طبقية بمفردات إضافية.

**استخدم Protocols للمنافذ ومُحاكيات للاختبارات.** تتيح لك `Protocol` في Python منافذ دون اقتران وراثة، وتطبيقات داخل الذاكرة تتيح لك اختبار حالات الاستخدام دون قاعدة بيانات — وهذا هو العائد الملموس الذي يجب أن تكون قادرًا على الإشارة إليه. إذا لم تستطع كتابة ذلك الاختبار الخالي من قاعدة البيانات، فالبنية ليست مطبَّقة فعلًا.

**برِّرها بقابلية الاختبار، لا بتبديل قاعدة البيانات.** اعتمدها لاختبار المنطق المعقد بمعزل وحماية نطاق قيِّم، لا من أجل ترحيل قاعدة بيانات لن تفعله. اكتب المبرر في ورقة (ADR، [`templates/adr.md`](../../templates/adr.md)) حتى يعرف المهندس اللاحق لماذا توجد هذه الطقوس — ويستطيع إزالتها إذا تبيَّن أن النطاق أبسط مما ظُن.

## Anti-Patterns

**Clean Architecture Everywhere.** التطبيق كله في كيانات ومنافذ ومحولات ومُحوِّلات، بما في ذلك ميزات هي CRUD صِرف — التحذير المسمَّى في الدستور. يضاعف كل تغيير تافه بكل الطقوس. العلامة: كيان إعدادات من حقلين له منفذه ومحوله ومُحوِّله الخاص.

**The ORM Entity.** "كيانات" نطاق هي نماذج SQLAlchemy، تقرن النواة بالاستمرارية بينما تعرض مجلدات Clean Architecture. قاعدة الاعتمادية تُنتهك بشكل غير مرئي. العلامة: `domain/entities.py` يستورد `sqlalchemy`.

**Wrong-Way Ports.** واجهات مُعرَّفة في طبقة البنية التحتية بحيث لا تزال الاعتمادية تشير إلى الخارج — بنية طبقية متنكرة بهيئة سداسية. العلامة: واجهة المستودع تعيش بجوار تنفيذها في SQLAlchemy، لا مع حالة الاستخدام.

**The Anemic Use Case.** حالات استخدام تكتفي بإعادة التوجيه إلى المستودعات دون تنسيق أو قواعد — الطقوس بلا جوهر، ما يثبت أن الوحدة لم تكن بحاجة إلى البنية. العلامة: كل حالة استخدام تفويض بسطر واحد.

**Framework Leakage.** أنواع ويب أو ORM أو تسلسل تظهر في طبقات النطاق أو التطبيق، لتنهي بصمت الاستقلال عن أُطر العمل الذي وجدت البنية لتوفيره. العلامة: ظهور `Request` أو `Session` في توقيع حالة استخدام.

## Decision Tree

"هل أستخدم Clean Architecture لهذا الجزء من النظام؟"

```
Does this part have a COMPLEX, VALUABLE domain core — real business rules,
worth testing exhaustively, that should outlive infrastructure choices?
│
├── NO  (CRUD, simple domain, thin logic, short-lived) 
│        └──► Do NOT use Clean Architecture. Use layered (Ch 01) or
│             feature-based (Ch 02). The ceremony would be pure cost.
│
└── YES (e.g. a matching engine, pricing engine, rules/risk model)
     │
     Apply Clean Architecture to THIS module only:
     │
     ├─ Domain entities = plain dataclasses (no ORM, no framework).
     ├─ Use cases depend only on PORTS (Protocols) they own.
     ├─ Adapters implement the ports and map ORM <-> domain, on the outside.
     ├─ Controllers convert framework objects to domain types at the boundary.
     └─ Prove it: a use-case test that runs with in-memory fakes, no database.
     │
     Can you write that database-free test?
     ├── YES ──► The architecture is real. Keep the rest of the app simpler.
     └── NO ───► The Dependency Rule is being violated somewhere. Find the
                 inward-pointing arrow that shouldn't exist and fix it — or
                 conclude this module didn't need Clean Architecture.
```

## Checklist

### Implementation Checklist

- [ ] Domain entities are plain dataclasses; the domain layer imports no framework or ORM.
- [ ] Ports are defined in the application layer, with the use cases that depend on them.
- [ ] Use cases depend only on ports; they import no adapter, no SQLAlchemy, no FastAPI.
- [ ] Adapters implement the ports and perform the ORM ↔ domain mapping.
- [ ] Controllers convert framework objects to domain types before calling a use case.
- [ ] A use-case test runs with in-memory fake adapters and no database.

### Architecture Checklist

- [ ] Every source dependency points inward; nothing in the core references the outer layers.
- [ ] This architecture is applied only to the complex domain core, not to CRUD features.
- [ ] Domain entities and ORM models are separate types.
- [ ] The decision to use Clean Architecture here is recorded (ADR) with its justification.
- [ ] The justification is testability / domain protection — not a hypothetical database swap.

### Code Review Checklist

- [ ] No inner-layer file imports an adapter, SQLAlchemy, or a concrete repository (grep the core).
- [ ] No domain "entity" is secretly an ORM or Pydantic model (watch AI diffs especially).
- [ ] No framework type leaked into a use-case or domain signature.
- [ ] Ports are owned by the inner layer, not the adapter layer.
- [ ] Use cases contain real orchestration/rules, not pure pass-throughs.

*(A Deployment Checklist is not applicable — Clean Architecture is a
code-organization concern. Deployment topology is Chapter 04.)*

## Exercises

**1. Invert a dependency.** خذ حالة استخدام التسوية وأَعِد هيكلتها بحيث تعتمد على منفذ `PaymentRepository` (Protocol) تملكه، مع محول SQLAlchemy ينفِّذه. ثم اكتب اختبارًا يمارس حالة الاستخدام بمستودع مُحاكاة داخل الذاكرة ودون قاعدة بيانات. المُخرَج هو الشيفرة مضافًا إليها اختبار ناجح بلا قاعدة بيانات — دليل ملموس على أن قاعدة الاعتمادية محفوظة.

**2. Find the wrong-way arrow.** خذ وحدة تدَّعي أنها Clean Architecture (سواء كانت لك، أو أنتجها مساعد من طلب ساذج "ابنِ هذا بـ Clean Architecture") وراجِعها بحثًا عن انتهاكات: ORM ككيان، منافذ في طبقة المحولات، أنواع أُطر في النواة، الطبقات الداخلية تستورد إلى الخارج. المُخرَج قائمة الانتهاكات مع سهم الداخل الذي يكسره كل منها والإصلاح.

**3. The "should we?" call.** بالنظر إلى ثلاثة أجزاء من منتج — ميزة فواتير CRUD، ومحرك تسوية/مطابقة معقد، وصفحة إعدادات ثابتة — قرِّر لكل جزء هل يستحق Clean Architecture، وبرِّر القرار في جملتين أو ثلاث لكل جزء. المُخرَج القرارات الثلاث؛ والمغزى أن الإجابة الصادقة هي "نعم" لواحد فقط منها بالضبط، وهذا هو الحكم الذي يدور حوله الفصل كله.

## Further Reading

- **The Clean Architecture** (Robert C. Martin — منشور المدونة لعام 2012 وكتاب 2017) — مصدر قاعدة الاعتمادية والدوائر المتركزة. اقرأ منشور المدونة أولًا للقاعدة؛ ثم الكتاب للاستدلال والدراسات المعالجة الكثيرة.
- **Hexagonal Architecture (Ports and Adapters)** (Alistair Cockburn) — الصياغة الأصلية، وهي لمعظم تطبيقات الويب الصياغة الأنظف للفكرة نفسها: نواة تطبيق لها منافذ، ومحولات تركَّب عليها. كثيرًا ما تكون نموذجًا ذهنيًا أفضل من دوائر Clean الأربع الكاملة.
- **Architecture Patterns with Python** (Harry Percival وBob Gregory، مجاني على cosmicpython.com) — المعالجة Pythonية الحاسمة للمنافذ والمحولات وعكس الاعتمادية، مع هذه الحزمة بالذات. فصول نمط المستودع وطبقة الخدمة توضح كيف تبني (وكيف لا تفرط في بناء) البنية في هذا الفصل.
- **The Onion Architecture** (Jeffrey Palermo) — الصياغة الشقيقة، تستحق القراءة لترى أن Clean وHexagonal وOnion عائلة واحدة لها قاعدة واحدة (الاعتمادية تشير إلى الداخل)، فتتعرف على النمط تحت أي من أسمائه.
