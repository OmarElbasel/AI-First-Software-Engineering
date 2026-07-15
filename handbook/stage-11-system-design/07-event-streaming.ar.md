# تدفّق الأحداث (Event Streaming)

## المقدمة

قوائم الانتظار في الفصل الخامس لها سلوك محدد: الرسالة التي تُستهلَك هي رسالة ذهبت. هذا مناسب تمامًا للعمل — يجب أن يُعالَج ملف PDF مرة واحدة — لكنه خاطئ تمامًا للحقائق (facts). عند إصدار فاتورة، تهتم بها *أربعة* أجزاء في نظام Invoicely: مُرسِل الـ webhook يجب أن يُخطِر أنظمة العميل، وتجمّعات التحليلات يجب أن تُحدَّث، وسجلّ التدقيق (audit trail) يجب أن يسجّلها، وفهرس البحث يجب أن يعكسها. إن نمذجت ذلك باستخدام قوائم الانتظار، فإما أن تُدرج في الطابور أربع رسائل لكل حقيقة (المنتج يعرف الآن كل مستهلِك — وهذا اقتران ينمو مع كل ميزة جديدة) أو أن تسمح للمستهلِكين بالاستعلام من قاعدة البيانات المعاملاتية (وهو الحمل الذي عمل الفصل 01 بجد لإزالته، ثم يعود متسلّلًا). يحلّ التدفّق (stream) المشكلة بنيويًا: تُلحَق الحقائق بسجلّ (log) متين ومرتّب، يستطيع أي عدد من المستهلِكين قراءته *بشكل مستقل، وفق إيقاعهم، دون استهلاك أي شيء* — ويمكنهم إعادة قراءته من أي نقطة.

السجلّ هو آخر نموذج ذهني تضيفه هذه المرحلة، وأكثرها عمومية: السجلّات المُقسَّمة إلى أقسام (partitions) والملحَق فقط (append-only) مع إزاحات (offsets) يتتبّعها المستهلِك هي الطريقة التي يعمل بها Kafka، والتي تعمل بها Redis Streams، والتي تعمل بها تكرار قواعد البيانات (WAL في المرحلة 6 سجلّ؛ والتكرار في الفصل 04 هو شحن سجلّ)، والتي تُبنى بها معظم بنية البيانات التحتية واسعة النطاق. وهو أيضًا — كما ذكرت README المرحلة منذ البداية — **المكوّن الذي غالبًا ما يُتَبَنَّى في وقت أبكر مما ينبغي**. فريق مكوّن من ثلاثة أشخاص يُشغِّل عنقود Kafka لأربعين حدثًا في الساعة هو القصة النموذجية للتوسّع المبكر، ولهذا يعلّم هذا الفصل نموذج السجلّ بشكل محايد تجاه المورّد، وينفّذه على Redis الموجودة بالفعل في الحزمة، ويذكر بدقة ما الذي سيُجبِر على الانتقال إلى Kafka — بحيث يكون القرار، متى جاء، قرارًا حسابيًا لا قرارًا موضة.

حدود واضحة: *العمارة المعتمدة على الأحداث (event-driven architecture) كاسلوب تصميمي* — الأحداث مقابل الأوامر، التناغم (choreography) مقابل التنسيق (orchestration)، ومشكلة الكتابة المزدوجة (dual-write) ونمط صندوق الصادر (outbox) — هي المرحلة 2، الفصل 07، ويُفترض الإلمام بها هنا. هذا الفصل هو البنية التحتية التي تعمل عليها تلك التصاميم على نطاق واسع: الأقسام (partitions)، مجموعات المستهلِكين (consumer groups)، الإزاحات (offsets)، الاستبقاء (retention)، إعادة التشغيل (replay)، تطوّر المخططات (schema evolution)، وحكم متى يستحق السجلّ عناءه.

## لماذا هذا مهم

- **التوزيع المتشعّب (fan-out) هو نمط النمو الذي لا تستطيع قوائم الانتظار التعبير عنه.** كل منتج ناضج يزيد من عدد مستهلِكي الحقائق نفسها: التحليلات، التدقيق، البحث، webhooks، مستودع البيانات، كاشف الاحتيال. مع السجلّ، إضافة المستهلِك السادس هي *صفر تغييرات في المنتج* — مجموعة جديدة تقرأ التدفّق نفسه. بدونه، كل إضافة إما أن تعدّل المنتج أو تزيد الحمل على قاعدة البيانات المعاملاتية.
- **يُخرج أحمال عمل كاملة من قاعدة البيانات.** الهدف النهائي للفصل 01: تجميع التحليلات، وفهرسة البحث، واستعلامات التدقيق تعمل ضد *إسقاطات* (projections) يغذّيها التدفّق — وليس ضد PostgreSQL التي تعالج المدفوعات. التدفّق هو الطريقة التي تغادر بها أحمال القراءة المنزل دون أن تفقد التواصل.
- **إعادة التشغيل تحوّل استرداد الأخطاء من جراحة إلى حساب.** خطأ في إسقاط (الإحصائيات عدّت إشعارات الدائن مرتين لأسبوع) يُصلَح بـ: إصلاح الكود، إعادة ضبط إزاحة المجموعة، إعادة البناء. بدون إعادة التشغيل، هذا إعادة بناء جنائي من قاعدة البيانات المعاملاتية — إذا كانت البيانات لا تزال موجودة بشكل قابل للاستعلام أصلًا.
- **الترتيب (ordering) أصبح متاحًا أخيرًا في المكان الذي يهم فيه.** ساوى الفصل 05 بين أن المستهلِكين المتوازيين يُدمّرون الترتيب. السجلّات المُقسَّمة تستعيد النسخة المفيدة: ترتيب صارم *لكل مفتاح* (لكل مستأجر، لكل فاتورة) مع التوازي *عبر* المفاتيح — وهو العقد الذي يحتاجه فعلًا مستهلِكو الـ webhook ومسارات التدقيق.
- **النسخة المبكرة تكلّف مالًا وجهدًا حقيقيين.** Kafka نظام موزّع ذو حالة (stateful) له أنماط فشل خاصة به، وتخطيط سعة، وحلقة ترقيات مستمرة. إن اعتُمد قبل وجود نمط التشعّب، فهو تكلفة حمل بحتة — التحذير المركزي للمرحلة، وهو الآن في أقصى حدّته، لأن التدفّق هو الطبقة الأكثر عرضة لضغوط الاعتماد التي تحرّكها المؤتمرات.

## النموذج الذهني

**السجلّ: ملحَق فقط، مُعَنوَن بالإزاحة (offset)، وغير إتلافي عند القراءة.**

```
            THE STREAM (an append-only log)
  offset:   0     1     2     3     4     5     6    ...
          ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┐
          │ evt │ evt │ evt │ evt │ evt │ evt │ evt │ ◄─ producers
          └─────┴─────┴─────┴─────┴─────┴─────┴─────┘    append only
                        ▲                   ▲
        group "analytics"                   group "webhooks"
        is at offset 2                      is at offset 5
        (its own bookmark,                  (independent pace,
         its own pace)                       same events)

  Reading moves YOUR bookmark; it deletes nothing. Retention —
  time- or size-based — is what eventually trims the tail.
  Replay = moving a bookmark backward. That's the whole trick.
```

**الأقسام (Partitions): التوازي والترتيب، بآلية واحدة.** التدفّق مُقسَّم إلى P قسمًا؛ كل حدث يُوجَّه عبر *مفتاح القسم* (partition key) الخاص به (تجزئة tenant_id مثلًا). ينتج عن ذلك ضمانتان: الأحداث التي لها نفس المفتاح تقع في نفس القسم وبترتيب الإلحاق (ترتيب لكل مفتاح)، والأقسام المختلفة يمكن استهلاكها بالتوازي. داخل مجموعة المستهلِكين، يملك كل قسم مستهلِكًا واحدًا بالضبط — لذا P هو الحد الأقصى لتوازي المجموعة، واختيار المفتاح يقرّر معًا ما هو المرتّب وكيف يتوزّع الحمل بالتساوي (مستأجر ضخم = قسم ساخن (hot partition)؛ مشكلة الانحراف (skew) تُختار عند تصميم المفتاح).

**مجموعات المستهلِكين (Consumer groups): قوائم الانتظار والنشر/الاشتراك، موحَّدة.** داخل مجموعة واحدة، المستهلِكون *يتنافسون* (كل حدث يُعالَج بواسطة عضو واحد — سلوك قائمة الانتظار). عبر المجموعات، كل مجموعة تحصل على *كل شيء* (سلوك النشر/الاشتراك). كل مجموعة تتتبّع إزاحاتها فقط. لهذا السبب إضافة المستهلِك السادس مجانية، ولهذا السبب الأسبوع البطيء لمجموعة واحدة (webhooks تُعيد المحاولة ضد نقاط نهاية معطّلة) لا يؤخّر أبدًا مجموعة أخرى (التحليلات تبقى محدّثة) — الضغط الخلفي (backpressure) لكل مجموعة، يظهر كـ *تأخّر* (lag) تلك المجموعة (مدى بُعد إشارتها المرجعية عن رأس التدفّق)، وهو عمر أقدم رسالة في طبقة التدفّق: الرقم الواحد الذي يجب التنبيه عليه.

**التسليم يظل عقد الفصل 05.** تأكيد الإزاحة (offset commit) بعد المعالجة = مرة واحدة على الأقل (at-least-once) (عطل بين العمل والتأكيد → إعادة معالجة)؛ التأكيد قبل المعالجة = مرة واحدة على الأكثر (at-most-once). "مرة واحدة بالضبط" تظل خاصية شاملة (end-to-end) تبنيها أنت: مستهلِكون عاطفيون (idempotent) مفاتيحهم معرّف الحدث (projectors: upsert؛ التأثيرات الجانبية: جدول إلغاء تكرار). لا شيء في السجلّ يُلغي قانون العاطفية — إعادة التشغيل، في الواقع، يُضاعف الالتزام به.

**إدخال الحقائق: مشكلة الكتابة المزدوجة، مرة أخرى.** النشر في التدفّق *و* الالتزام في PostgreSQL هما نظامان — فخ الكتابة المزدوجة في المرحلة 2 حرفيًا. الإجابة أيضًا من المرحلة 2: **صندوق الصادر (outbox)** — أحداث تُكتب في جدول صندوق الصادر *في نفس المعاملة* (transaction) التي تخصّ تغيير الحالة، وتُنقَل إلى التدفّق بواسطة عملية منفصلة. (تعميمه الصناعي هو CDC — Debezium يتبع WAL قاعدة البيانات نفسها — يستحق المعرفة كمصير لنفس الفكرة.) قاعدة جانب المنتج التي يحقّقها هذا: **قاعدة البيانات تلتزم بالحقيقة؛ التدفّق ينشرها؛ لا شيء ينشر ما لم يُلتزَم به.**

**نوعان من المستهلِكين، سياسة إعادة تشغيل واحدة لكل منهما.** *ال projectors* تبني الحالة (جداول التحليلات، فهارس البحث): عاطفية بالبناء (upsert بالمفتاح)، آمنة لإعادة البناء من الإزاحة صفر، إعادة التشغيل هي قوتها الخارقة. *منفّذو التأثيرات الجانبية (side-effectors)* يتصرّفون في العالم (يُرسلون webhooks، رسائل بريد إلكتروني): إعادة التشغيل يجب *ألا* تُعيد إطلاقها — يلغون التكرار حسب معرّف الحدث، وإزاحات مجموعاتهم لا تُعاد ضبطها بشكل عابر. الخلط بين الاثنين هو كيف تُعيد إعادة بناء projector إرسال شهر من webhooks.

تعريف عملي:

> **تدفّق الأحداث هو سجلّ مُقسَّم وملحَق فقط للحقائق، يُغذَّى معامليًا عبر صندوق صادر، مفاتيحه تجعل الترتيب يتبع الكيان الذي يحتاجه، يُحتفَظ به لفترة كافية لجعل إعادة التشغيل أداة، ويقرأه مجموعات مستهلِكين مستقلة — projectors قد تُعيد البناء من الصفر، ومنفّذو تأثيرات جانبية يجب ألا يُعيدوا الإطلاق أبدًا — كل مجموعة تُراقَب حسب تأخّرها. يستحق تعقيده عندما يحتاج عدة مستهلِكين إلى الحقائق نفسها بشكل مستقل؛ قبل ذلك اليوم، قوائم الانتظار في الفصل 05 هي الأداة المناسبة.**

## مثال إنتاجي

مُحفِّز Invoicely ملموس: أظهر اختبار الحمل في الفصل 01 أن تجميع لوحة تحكم التحليلات واستعلامات التدقيق تُسهم بنحو 30% من حمل PostgreSQL، وأن مُرسِل الـ webhook يقرأ حالة الفاتورة عند كل تسليم، وخارطة الطريق تضيف فهرس بحث وتصديرًا إلى مستودع بيانات — المستهلِكان الرابع والخامس للحقائق نفسها. التصميم:

- **تدفّق واحد لكل تجميعة مجال (domain aggregate):** `invoice-events` (مُصدَرة، مُرسَلة، تمّت مشاهدتها، مدفوعة، مُلغاة، تم إرسال تذكير...)، `payment-events`. ليس `events` ناري عملاق واحد — التدفّقات عقود، والعقود لها أصحاب (حدود الوحدات في المرحلة 2).
- **مفتاح القسم: `tenant_id`.** ترتيب لكل مستأجر (مشترِك الـ webhook الخاص بالمستأجر يرى *صادرة → مدفوعة* بالترتيب، دائمًا)، توازي عبر آلاف مستأجري Invoicely، خطر المستأجر الساخن مُقبَل ومُراقَب (أكبر مستأجر أقل من 2% من الحجم).
- **جانب المنتج: صندوق الصادر** الذي بنته Invoicely بالفعل لأحداث المرحلة 2 داخل العملية، يُنقَل الآن إلى التدفّق بواسطة مهمة مجدولة بإيقاع (beat) (المستوى الفردي في الفصل 03).
- **أربع مجموعات مستهلِكين:** `analytics` (projector: upserts في جداول تجميعية — لوحات التحكم تغادر قاعدة البيانات المعاملاتية)، `audit` (projector: مخزن تدقيق ملحَق فقط)، `search` (projector: تحديثات فهرس)، `webhooks` (side-effector: يُلغي التكرار حسب معرّف الحدث، يغذّي *قائمة انتظار* الـ webhook في الفصل 05 — التدفّق يوزّع الحقائق؛ قائمة الانتظار لا تزال تقوم بعمل التسليم بآليات إعادة المحاولة/DLQ. التدفّقات وقوائم الانتظار تتآلف؛ لا تتنافس).
- **التقنية: Redis Streams** على نسخة الحالة (state instance) في الفصل 04 — الحجم المُقاس نحو 50 ألف حدث/يوم (نحو 0.6/ثانية في المتوسط، 20/ثانية في ذروة نهاية الشهر)، الاستبقاء 14 يومًا ≈ 700 ألف حدث ≈ داخل ميزانية الذاكرة تمامًا. محفّزات الانتقال المكتوبة إلى Kafka: احتياج الاستبقاء يتجاوز اقتصاديات الذاكرة (أشهر من السجل، أو أكثر من 10 جيجابايت)، إنتاجية مستدامة تتجاوز الآلاف القليلة/ثانية، احتياجات نظام CDC/الموصلات (connectors)، أو منظمة متعددة الفرق حيث تصبح التدفّقات العقد بين الخدمات. لا شيء من هذا قريب؛ المذكرة مؤرخة وتُعاد مراجعتها مع نموذج الحمل.

## هيكل المجلدات

```
app/
└── events/
    ├── schemas/
    │   ├── envelope.py         # THE envelope: event_id, type, version,
    │   │                       #   occurred_at, tenant_id, payload —
    │   │                       #   every event, no exceptions
    │   └── invoice_events.py   # typed payloads per event type; the
    │                           #   stream's contract lives in the repo,
    │                           #   evolves additively, and is imported
    │                           #   by producers AND consumers (drift
    │                           #   becomes an import error, not a 3am page)
    ├── outbox.py               # Stage 2's outbox table + the relay:
    │                           #   same-transaction insert, beat-driven
    │                           #   publish — the only door to the stream
    ├── stream.py               # XADD/XREADGROUP/XACK/XAUTOCLAIM wrapped
    │                           #   once: consumer-group mechanics are
    │                           #   infrastructure, not per-feature code
    └── consumers/
        ├── analytics.py        # projector — upserts, rebuildable
        ├── audit.py            # projector — append-only store
        ├── search.py           # projector — index updates
        └── webhook_fanout.py   # side-effector — dedups, enqueues to
                                #   Ch 05's webhook lane; NEVER rebuilt
infrastructure/
└── compose/
    └── docker-compose.prod.yml # one consumer service per group —
                                #   groups scale and deploy independently,
                                #   which was the whole point
```

تتكرر الحجة البنيوية مرة أخرى: العقود (schemas)، الباب الوحيد (outbox)، والميكانيكا (stream.py) يعيش كل منها في مكان واحد قابل للمراجعة تمامًا — لأن نمط فشل أنظمة التدفّق ليس كودًا ينكسر، بل عقودًا تنحرف (drift).

## التنفيذ

المغلف (envelope) — جزء المخطط الذي لا يتغيّر شكله أبدًا:

```python
# app/events/schemas/envelope.py
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

class EventEnvelope(BaseModel):
    event_id: UUID          # the idempotency key for every consumer
    event_type: str         # "invoice.paid"
    version: int            # payload schema version — consumers accept
                            # v N and N-1 during migrations (additive
                            # evolution: add fields, never remove/rename)
    occurred_at: datetime   # business time, from the producer
    tenant_id: UUID         # partition key + the multi-tenancy floor
    payload: dict           # validated against the typed schema for
                            # event_type/version at both ends
```

مرحّل صندوق الصادر (outbox relay) — الباب الوحيد المعاملي إلى التدفّق (صندوق الصادر في المرحلة 2، نما له وجهة):

```python
# app/events/outbox.py
from app.core.redis import state_redis
from app.core.db import session_scope
from app.models.ops import OutboxEvent

STREAM_MAXLEN = 1_000_000   # size backstop; retention policy is 14 days,
                            # trimmed by a beat task — BOTH live inside
                            # the Ch 04 state-instance memory budget

async def relay_outbox_batch(batch_size: int = 500) -> int:
    """Beat-scheduled (Ch 03 singleton). Reads committed-but-unpublished
    outbox rows IN COMMIT ORDER, appends to the stream, marks published.
    Crash-safe: re-running re-publishes at most the last batch — which
    is why event_id idempotency is every consumer's law."""
    async with session_scope() as db:
        rows = await OutboxEvent.unpublished(db, limit=batch_size)
        for row in rows:
            await state_redis.xadd(
                f"stream:{row.stream}",
                {"envelope": row.envelope_json},
                maxlen=STREAM_MAXLEN,
                approximate=True,
            )
            row.mark_published()
        return len(rows)
```

ميكانيكا مجموعة المستهلِكين، ملفوفة مرة واحدة (أسماء Redis Streams في الكود، أسماء Kafka في التعليقات — المفاهيم هي الجزء المحمول):

```python
# app/events/stream.py
from app.core.redis import state_redis

async def consume(stream: str, group: str, consumer: str, handler) -> None:
    """At-least-once consumer loop.
    XREADGROUP ≈ poll; XACK ≈ offset commit; the PEL (pending entries
    list) ≈ delivered-but-uncommitted; XAUTOCLAIM ≈ partition rebalance
    reclaiming a dead consumer's work."""
    while True:
        # 1) reclaim events a crashed group-member left unacked >5 min
        claimed = await state_redis.xautoclaim(
            stream, group, consumer, min_idle_time=300_000, count=50
        )
        # 2) then read new events
        fresh = await state_redis.xreadgroup(
            group, consumer, {stream: ">"}, count=100, block=5_000
        )
        for msg_id, fields in _entries(claimed, fresh):
            envelope = parse_envelope(fields)
            await handler(envelope)          # idempotent — see consumers
            await state_redis.xack(stream, group, msg_id)   # ACK LAST
```

projector — عاطفي بالبناء، قابل لإعادة البناء حسب السياسة:

```python
# app/events/consumers/analytics.py
async def handle(envelope: EventEnvelope) -> None:
    """Projector: UPSERT keyed on natural keys, so replaying any event
    (crash redelivery or full rebuild) converges instead of double-
    counting. Rebuild = reset THIS group's offset to 0 and let it run;
    the transactional DB is never involved."""
    match envelope.event_type:
        case "invoice.paid":
            await aggregates.upsert_revenue(
                tenant_id=envelope.tenant_id,
                month=envelope.occurred_at.date().replace(day=1),
                invoice_id=envelope.payload["invoice_id"],   # natural key:
                amount=envelope.payload["total"],            # re-apply = no-op
            )
        case _:
            pass   # projectors ignore types they don't project — this
                   # tolerance is what makes ADDING event types free
```

منفّذ التأثير الجانبي — الذي يجب أن ينجو من إعادة التسليم *و* من أخطاء إعادة التشغيل البشرية:

```python
# app/events/consumers/webhook_fanout.py
async def handle(envelope: EventEnvelope) -> None:
    """Side-effector: dedup by event_id BEFORE any effect. The dedup row
    is the guard against redelivery AND against an accidental offset
    reset — a replayed event hits the dedup and dies here, silently,
    instead of re-sending a month of webhooks."""
    if not await dedup.claim(f"wh:{envelope.event_id}", ttl_days=30):
        return
    for sub in await subscriptions.for_event(envelope.tenant_id, envelope.event_type):
        deliveries.enqueue(sub.id, envelope)   # → Ch 05's webhook lane:
                                               # retries/DLQ live there
```

وتنبيه المستوى الوحيد، التأخّر لكل مجموعة (شقيق التدفّق لمقياس العمر في الفصل 05): مهمة بإيقاع تقرأ عدد المعلَّق لكل مجموعة والمسافة إلى الرأس وتصدّر `stream.lag{group=...}` — يتم التنبيه ضد SLO كل مجموعة على حدة (التحليلات: 5 دقائق؛ توزيع webhooks: دقيقة واحدة؛ البحث: ساعة مقبولة).

## قرارات هندسية

### تدفّق أم قائمة انتظار أم لا شيء؟

القرار الذي يسبق كل القرارات الأخرى. **قائمة انتظار** (الفصل 05) عندما تكون الرسالة *عملًا* (work) لفئة مستهلِك واحدة بالضبط ولا قيمة لسجلّها التاريخي. **تدفّق** عندما تكون الرسالة *حقيقة* يحتاجها ≥2 مستهلِكَين مستقلَّين، أو عندما يكون الترتيب لكل مفتاح أو إعادة التشغيل متطلّبًا. **لا شيء** — استدعاء مباشر أو أحداث داخل العملية في المرحلة 2 — عندما يكون هناك مستهلِك واحد وهو في نفس قاعدة الكود؛ المستهلِك الرابع، لا الأول، هو عندما يربح التدفّق. التآلف طبيعي: تدفّق Invoicely يوزّع الحقائق إلى مجموعة تُدرج *عملًا في قائمة الانتظار* — التدفّقات للتوزيع، قوائم الانتظار للتنفيذ.

### ما هو مفتاح القسم؟

الكيان الذي يجب أن تبقى أحداثه مرتّبة — وهو عقد، وليس مقبض ضبط: تغييره لاحقًا يكسر الترتيب لكل مفتاح عبر الحدود. `tenant_id` عندما يفكّر المستهلِكون لكل مستأجر (هكذا يفعل Invoicely)؛ `invoice_id` لتوازي أدقّ عندما يهم فقط الترتيب لكل كيان؛ أبدًا عشوائي (هذا اختيار للفوضى مقابل إنتاجية لا تملكها)، أبدًا ثابت (هذا عنق زجاجة لمستهلِك واحد بزيّ تدفّق). تحقّق من الانحراف (skew): نصيب أكبر مفتاح من الحجم هو السقف لمدى اختلال توازن الاستهلاك.

### كم مدة الاستبقاء — ومن يدفع ثمنه؟

الاستبقاء = نافذة إعادة التشغيل = أفق إعادة بناء projector = عمق الرجوع للمستهلِك الجديد. الأطول أقدر بصراحة وأغلى بصراحة — وعلى Redis Streams العملة هي *ذاكرة* نسخة الحالة في الفصل 04، مما يجعل الحساب الميزانياتي إلزاميًا: الأحداث/يوم × الحجم × الأيام، مع سقف خلفي MAXLEN للارتفاعات. استبقاء Invoicely البالغ 14 يومًا يغطي "إصلاح خطأ projector اكتُشف خلال sprint"؛ إعادة بناء إسقاطات *أقدم* تعود إلى تصدير من مصدر الحقيقة (قاعدة البيانات لا تزال هي الحقيقة — انظر حدود event sourcing أدناه). عندما يريد الاستبقاء أن يكون أشهر، يكون هذا أحد محفّزات Kafka المكتوبة التي تطلق.

### كيف تتطوّر المخططات دون كسر خمسة مستهلِكين؟

الإضافة فقط (additive-only) كقانون دائم: الحقول الاختيارية الجديدة وأنواع الأحداث الجديدة مجانية (projectors تتجاهل الأنواع المجهولة بالتصميم)؛ عمليات إعادة التسمية والإزالة والتغييرات الدلالية هي `version` جديد، مع قبول المستهلِكين لـ N و N−1 خلال نافذة الترحيل. المخططات تعيش في المستودع (repo) وكلا الجانبين يستوردها — انحراف المنتج/المستهلِك يصبح خطأ نوعي (type error) في وقت CI (حجة اختبار العقد في المرحلة 8، مطبَّقة على الأحداث). القاعدة التي تحافظ على صدق كل هذا: الأحداث تصف *ما حدث* بمصطلحات العمل (`invoice.paid`، المبلغ، المستأجر) — ليست فروقات صفوف، ولا "ما يحتاجه المستهلِك هذا الأسبوع" (أحداث-لا-أوامر في المرحلة 2، لا تزال القانون).

### Redis Streams أم Kafka — وما الذي يُجبِر على الانتقال؟

تفوز Redis Streams على مقياس Invoicely بحجة بسيطة: دلالات السجلّ التي يحتاجها هذا الفصل (إلحاق، مجموعات، تأكيدات (acks)، مطالبات (claims)، تقليم) بدون أي مكوّنات جديدة، على نسخة مُهندَسة بالفعل في الفصل 04. مزايا Kafka الحقيقية — الاستبقاء المُسعَّر بالقرص (أشهر، تيرابايتات)، الإنتاجية العالية المستدامة مع التوسع على مستوى القسم، نظام الموصلات/CDC، عقود المواضيع بين الفرق مع ACLs وسجلّ مخططات — هي بالضبط المحفّزات المكتوبة في مثال الإنتاج، ولا شيء منها تباهٍ بالحجم: كل واحد يُسمّي *قدرة* لا تستطيع Redis تقديمها، وليس رقمًا يبدو كبيرًا. عندما يأتي الانتقال، المفاهيم (وشكل كود هذا الفصل) تنتقل؛ `stream.py` هو الملف الوحيد الذي يتكلم Redis. Kafka المُدارة (MSK، Confluent) هي *شكل* الانتقال الافتراضي — تشغيل كوورومات ZooKeeper/KRaft ليس إلى أين يجب أن يذهب انتباه فريق المنتج (حجة LB المُدارة في الفصل 02، برهانات أعلى).

## المفاضلات

| الخيار | ما تكسبه | ما تدفعه |
|---|---|---|
| تدفّق (بدل N قوائم انتظار) للحقائق | المنتج منفصل عن عدد المستهلِكين؛ إعادة التشغيل؛ ترتيب لكل مفتاح | سجلّ يجب تشغيله؛ ميزانية استبقاء؛ انضباط مجموعة المستهلِكين |
| قوائم الانتظار فقط | آلة الفصل 05 التي تشغّلها بالفعل | المنتج يعرف كل مستهلِك؛ لا إعادة تشغيل؛ التوزيع المتشعّب = N إدراج في الطابور |
| مرحّل صندوق الصادر | لا كتابة مزدوجة، ترتيب الالتزام محفوظ | تأخّر المرحّل (ثوانٍ)؛ تآكل جدول صندوق الصادر؛ مهمة إيقاع إضافية |
| نشر مباشر من الطلب | أقل تأخّر | خطأ الكتابة المزدوجة، مضمون حتمًا (تحذير المرحلة 2) |
| مفتاح قسم tenant_id | الترتيب حيث يفكّر المستهلِكون؛ توزيع متقارب إلى حدّ ما | المستأجرون الضخام = أقسام ساخنة؛ تغيير المفتاح = كسر العقد |
| استبقاء طويل | إعادة تشغيل/إعادة رجوع أعمق؛ عمليات أبطأ | ذاكرة (Redis) أو قرص+عمليات (Kafka)؛ دائرة انفجار أكبر على أخطاء المخططات |
| فصل projector/side-effector | إعادة التشغيل آمنة بالبناء | انضباطا مستهلِكان يجب فرضهما في المراجعة |
| Redis Streams الآن | صفر مكوّنات جديدة؛ رافعة الفصل 04 | استبقاء مُسعَّر بالذاكرة؛ لا نظام بيئي؛ ترحيل في مستقبلك *إذا* أُطلقت المحفّزات |
| Kafka الآن | لن تهاجر أبدًا؛ نظام بيئي كامل | الفاتورة المبكرة النموذجية: نظام موزّع لـ 0.6 حدث/ثانية |
| Kafka مُدارة (عند الإجبار) | القدرة بدون عمليات الكووروم | التكلفة؛ اقتران بمزوّد؛ لا تزال مخططاتك ومفاتيحك وتأخّرك |

## الأخطاء الشائعة

- **اعتماد التدفّق قبل التوزيع المتشعّب.** مستهلِك واحد، وعقد Kafka، وشريحة عرض خارطة طريق — نمط البنية التحتية المبكرة الذي حاربته هذه المرحلة منذ الفصل 01، في أقصى صوره كلفة. عُدّ المستهلِكين المستقلّين؛ دون اثنين، استخدم الفصل 05.
- **النشر خارج صندوق الصادر.** `xadd` "سريع" داخل معالج الطلب، بجوار الالتزام في قاعدة البيانات — تعود الكتابة المزدوجة: الالتزام ينجح + النشر يفشل (المستهلِكون لا يعرفون أبدًا) أو النشر ينجح + الالتزام يتراجع (المستهلِكون يتعلمون كذبة). باب واحد، معاملي، بدون استثناءات؛ المراجعة تبحث بـ grep عن `xadd` خارج `outbox.py`.
- **إعادة تشغيل التأثيرات الجانبية.** إعادة ضبط الإزاحة التي أعادت بناء التحليلات *وأعادت* إرسال أربعة أسابيع من webhooks، لأن مجموعة واحدة قامت بالمهمتين. فصل projector/side-effector مع سياسة إعادة تشغيل لكل مجموعة هو الإصلاح البنيوي؛ جدول إلغاء التكرار هو حزام الأمان.
- **تأخّر غير مُراقَب.** مجموعة مستهلِكين عالقة لستة أيام — صفر أخطاء في أي مكان، لأن لا شيء *فشل*؛ توقّفت فحسب. التأخّر لكل مجموعة ضد SLOs كل مجموعة هو نبض المستوى؛ المجموعة بدون تنبيه تأخّر هي مجموعة متأخّرة بالفعل بصمت.
- **استبقاء بالعاطفة على مخزن مُسعَّر بالذاكرة.** "احتفظ بكل شيء، Redis بخير" — حتى يلتقي حجم نهاية الشهر بسقف الذاكرة في الفصل 04 وتصطدم نسخة الحالة (قائمة الحظر، قوائم الانتظار، *و* التدفّق) بقصة OOM مرة أخرى. الاستبقاء بند ميزانية: الأحداث × الحجم × الأيام، تُراجَع مع نموذج الحمل.
- **كسر المخطط لأن المنتج "يملكه".** حقل مُعاد تسميته يُشحن؛ ثلاث مجموعات مستهلِكين تبدأ في إرسال كل حدث إلى dead-letter. مخططات الأحداث عقود مشتركة ذات تطوّر إضافي فقط ومخارج ذات إصدارات — المنتج هو *حارسها* (steward)، لا مالكها.
- **مستهلِكون يقرؤون الرأس ويتخطّون المحاسبة.** `XREAD` عادي (بدون مجموعة، بدون ack) في أي شيء يتجاوز سكربت تصحيح: إعادة تشغيل تفقد الموقع (تخطّي أو إعادة معالجة كل شيء)، نسخة ثانية تعالج العالم مرتين. المجموعات، التأكيدات (acks)، ومطالبة المعطّل — الميكانيكا موجودة لأن كل واحدة منها تغطي فشلًا حقيقيًا.

## أخطاء الذكاء الاصطناعي

### Claude Code: عنقود Kafka لأربعين حدثًا في الساعة

اطلب من Claude Code "أضف تدفّق أحداث حتى تتمكّن التحليلات وwebhooks من استهلاك أحداث الفاتورة"، وستصل العمارة مكتملة التصنيع: Kafka (ثلاثة وسطاء، عامل التكرار 3)، سجلّ المخططات (schema registry)، Debezium CDC، اصطلاح تسمية المواضيع، ربما Flink زيادة في الخير — العمارة المرجعية من بيانات التدريب، حيث المحتوى المتعلق بالتدفّق مكتوب بشكل ساحق من قِبل ولشركات ذات حجم أكبر بأربعة مراتب. كل قطعة قابلة للدفاع عنها في مكان ما؛ *التركيب* منصة موزّعة مُثبَّتة على منتج يُنتج 0.6 حدث في الثانية، وتكلفة حملها تهبط على فريق مكوّن من ثلاثة أشخاص إلى الأبد.

**الاكتشاف:** الاقتراح يُسمّي التقنيات قبل الأحجام؛ لا يظهر رقم أحداث-في-الثانية في أي مكان؛ قائمة المكوّنات تتجاوز قائمة المستهلِكين. **الإصلاح:** انضباط الفصل 01، حرفيًا — زوّد المساعد بالحمل المُقاس والحزمة الموجودة، واطلب من التصميم أن يذكر ما هي أدرَج أبسط كافٍ و*ما المحفّز الذي سيُجبِر الدرجة التالية*. "Redis Streams حتى هذه الشروط الثلاثة المكتوبة" هو شكل الإجابة الصحيحة.

### GPT: إعادة تشغيل تُعيد إرسال كل بريد إلكتروني

يكتب GPT كود مستهلِك بليغ تتشابك فيه الإسقاطات والتأثيرات الجانبية — حدّث التجميع، أرسل الإشعار، فهرس المستند، كل ذلك في معالج واحد — لأن معظم مستهلِكي البرامج التعليمية يوضّحون كل شيء في دالة واحدة. الكود صحيح عند التسليم الأول وخاطئ تحت السمة المُحدِّدة للسجلّ: أي إعادة تشغيل (إعادة تسليم بعد عطل، إعادة ضبط إزاحة، إعادة بناء projector) تُعيد تنفيذ التأثيرات الجانبية. الفشل يشحن بصمت وينفجر عند أول استخدام تشغيلي لإعادة التشغيل — إعادة بناء التحليلات التي تُعيد إخطار كل عميل بكل فاتورة منذ مارس.

**الاكتشاف:** تأثيرات خارجية (بريد إلكتروني، webhooks، APIs الطرف الثالث) وupserts للحالة في نفس المعالج؛ لا إلغاء تكرار-حسب-event_id في أي مسار مؤثّر؛ طلب السحب (PR) لا يذكر سياسة إعادة تشغيل المجموعة. **الإصلاح:** فرض الفصل بنيويًا — projectors وside-effectors مستهلِكون مختلفون في مجموعات مختلفة بقواعد إعادة تشغيل مختلفة — واطلب مطالبة إلغاء التكرار كسطر أول في كل معالج مؤثّر، حتى إعادة ضبط إزاحة خاطئة تموت عند الحارس.

### Cursor: حلقة التدفّق التي تنسى إشارتها المرجعية

عند إكمال "اقرأ الأحداث من التدفّق"، يُنتج Cursor التعبير الاصطلاحي للبدء السريع: حلقة `while True` فوق `XREAD` عادي (أو مستهلِك Kafka بإعدادات `enable.auto.commit` الافتراضية ودون تفكير)، يتتبّع موقعه في متغيّر محلي. العرض التوضيحي مثالي. في الإنتاج، أول نشر يُعيد تشغيل العملية وتتبخّر الإشارة المرجعية — اعتمادًا على إزاحة البداية تعيد الحلقة معالجة أيام من الأحداث أو تتخطّى صمتًا كل ما فاتها؛ وسّع المستهلِك إلى نسختين وكلتاهما الآن تعالج كل حدث. لا مجموعة مستهلِكين، لا acks، لا مطالبة بالأقران المعطّلين: ثلاث ميكانيكا غائبة، ثلاثة أنماط فشل مُسلَّحة، صفر إخفاقات اختبار.

**الاكتشاف:** `XREAD` (وليس `XREADGROUP`) خارج أدوات التصحيح؛ موقع المستهلِك محفوظ في ذاكرة العملية؛ خدمات المستهلِكين بـ `replicas > 1` وبدون دلالات مجموعة؛ لا يوجد `XAUTOCLAIM`/معالجة إعادة توازن في أي مكان. **الإصلاح:** الحلقة الملفوفة في `stream.py` هي مسار الاستهلاك المُعتمَد الوحيد — كود الميزة يوفّر معالجًا، لا حلقته الخاصة — مما يحوّل فئة الأخطاء هذه برمتها إلى "لماذا يستورد هذا الملف redis مباشرة؟" في المراجعة.

## أفضل الممارسات

- **عُدّ المستهلِكين قبل الاعتماد؛ اكتب المحفّزات قبل التوسّع.** يدخل التدفّق عند ≥2 مستهلِكَين مستقلَّين للحقائق نفسها؛ الدرجة التالية (Kafka) تدخل عندما يطلق محفّز *مكتوب ومؤرَّخ* — محفّزات قدرة، لا تباهٍ بالحجم. كلتا المذكرتين تعيشان في المستودع (قالب ADR) وتُعاد مراجعتهما مع نموذج الحمل.
- **باب واحد للدخول (outbox)، حلقة واحدة للخروج (الملفوفة).** نقاط اختناق بنيوية تتفوّق على الانضباط: النشر خارج `outbox.py` والاستهلاك خارج `stream.py` إخفاقات مراجعة قابلة للاكتشاف بـ grep، وهو ما يجعل أخطاء الكتابة المزدوجة والإشارة المرجعية نادرة بدلًا من متكرّرة.
- **غلّف كل حدث؛ طوّر بشكل تراكمي؛ لخّص الاستثناءات في الإصدارات.** `event_id`، `type`، `version`، `occurred_at`، `tenant_id` على كل شيء — الحقول الخمسة التي تجعل العاطفية، التوجيه، الترحيل، التصحيح، وتعدّد المستأجرين ممكنة. تغييرات المخططات تُشحن مع اختبار عقد (contract test) يُشغَّل ضد كل مستهلِك.
- **افصل projectors عن side-effectors، واكتب سياسة إعادة تشغيل كل مجموعة.** Projectors: قابلة لإعادة البناء، upsert-عاطفية، عمليات إعادة ضبط الإزاحة أدوات روتينية. Side-effectors: محميّة بإلغاء التكرار، لا تُعاد ضبط الإزاحة إلا عبر runbook مع شخص ثانٍ. السياسة سطر واحد لكل مجموعة في ملف الطوبولوجيا.
- **تنبّه على التأخّر لكل مجموعة، ضد SLO تلك المجموعة.** بالإضافة إلى صحة المرحّل نفسه (عمر صندوق الصادر غير المنشور — التأخّر على جانب المنتج)، وذاكرة التدفّق ضد ميزانية الفصل 04. ثلاثة أرقام؛ المستوى هادئ أو يكذب.
- **تدرّب على إعادة التشغيل.** ربع سنوي: اكسر projectorًا في بيئة staging، أصلحه، أعِد الضبط، أعِد البناء، تحقّق من التقارب و— الاختبار الحقيقي — تحقّق من صفر تأثيرات جانبية أُطلِقت. إعادة التشغيل هي الميزة التي اشتريت السجلّ من أجلها؛ قدرة خارقة غير مُتدرَّب عليها حادثة مستقبلية بخطوات إضافية.
- **أبقِ الحقيقة في PostgreSQL.** التدفّق *تغذية حقائق مشتقّة* ذات استبقاء محدود؛ قاعدة البيانات تظل نظام السجلّ (system of record) مع النسخ الاحتياطية والقيود وآلات المرحلة 6. (Event sourcing — السجلّ *كـ* حقيقة — هو معمارية حقيقية لكن مختلفة بتكاليف مختلفة؛ اعتمادها يجب أن يكون قرارًا مع ADR خاص به، لا انحرافًا.

## الأنماط المضادة

- **العنقود المُلَقَّم للسيرة الذاتية (résumé cluster).** Kafka + registry + connect + لوحة تحكم لموضوع واحد يفعل أربعين حدثًا في الساعة — التوسّع المُحرَّك بالسيرة الذاتية في الفصل 01، صورته النهائية. يقول العمود الفقري كله للمرحلة: الدرجة المملّة التي تلبي الاحتياج المُقاس، مع محفّزات مكتوبة للتالية.
- **تدفّق كل شيء (everything-stream).** نار `events` واحد يحمل حقائق كل المجالات: كل مستهلِك يُحلّل كل شيء، ضمانات الترتيب لا تعني شيئًا (مفاتيح من مجالات مختلفة تتداخل)، حوكمة المخططات مستحيلة، والاستبقاء ميزانية واحدة لاحتياجات غير مترابطة. التدفّقات لكل تجميعة مجال، مملوكة مثل حدود الوحدات في المرحلة 2 التي تعكسها.
- **التدفّق كطابور عمل.** استخدام السجلّ لتوزيع وظائف قابلة لإعادة المحاولة — صياغة مهلات الرؤية يدويًا، إعادة المحاولات لكل رسالة، وDLQs من PELs ومطالبات — إعادة اختراع سيئة للفصل 05 (مرآة النمط المضاد lists-as-reliable-queues في الفصل 04). الحقائق تتدفّق عبر التدفّقات؛ العمل يتدفّق عبر قوائم الانتظار؛ مستهلِك التوزيع المتشعّب الذي يحوّل أحدهما إلى الآخر هو الجسر المُعتمَد.
- **Event sourcing بالصدفة.** "لدينا كل الأحداث — هل ما زلنا بحاجة إلى جدول الفواتير؟" — حذف نظام السجلّ لأن تغذية حقائق مدتها 14 يومًا ومحدودة الذاكرة ومتطوّرة تراكميًا *تُشبه* مخزن أحداث. ليست واحدة: لا لقطات (snapshots)، لا استبقاء أبدي، لا آلية upcasting، لا ضمانة إعادة بناء من التكوين (genesis). نسخة الانحراف من قرار معماري كبير هي أسوأ نسخة.
- **منطق عمل في الأنبوب.** إثراء وتصفية وتحويل الأحداث في المرحّل أو "معالج تدفّق" متنامٍ حتى يصبح الأنبوب تطبيقًا بلا مالك — ناقل خدمة المؤسسات (ESB)، وُلد من جديد. نقاط ذكية، أنابيب غبية (درس الخدمات الصغرى في المرحلة 2): المنطق يعيش في المنتجين والمستهلِكين، حيث لديه اختبارات وأصحاب.
- **استعلام التحليلات ضد التدفّق الخام.** الإجابة عن أسئلة المنتج بمسح السجلّ ("احسب أحداث الدفع هذا الشهر") — بطيء، محدود بالاستبقاء، ويُعدّ مرتين لكل إعادة تسليم. التدفّق *يُغذّي* الإسقاطات؛ الاستعلامات تضرب الإسقاطات. إذا كان لا يمكن الإجابة عن سؤال بأي إسقاط، فهذا projector جديد، وليس مسح سجلّ.

## شجرة القرار

```
Facts need to reach consumers — choose the machinery:
│
├─ How many INDEPENDENT consumers of the same facts?
│   ├─ 1, same codebase → direct call / Stage 2 in-process events
│   ├─ 1, needs retry/isolation → a queue lane (Ch 05)
│   └─ ≥2 (or hard need for per-key order / replay) → a stream ↓
├─ Which rung?
│   ├─ Volume fits memory-priced retention (Ch 04 budget math),
│   │  no ecosystem/CDC needs, one team → Redis Streams
│   ├─ A written trigger fired (months/TB retention, sustained
│   │  1000s/sec, connector ecosystem, cross-team contracts)
│   │  → Kafka — managed unless ops IS your product
│   └─ Unsure → the smaller rung + the triggers as an ADR
├─ Producer side:
│   └─ ALWAYS the outbox (same-transaction insert, relayed) —
│      direct publish from request code is the dual-write, rejected
├─ Partition key = the entity whose events must stay ordered
│   (tenant / entity id; never random, never constant; check skew)
├─ Retention = replay window you'll actually use, priced against
│   the store (memory vs disk); MAXLEN backstop for spikes
├─ Each consumer group:
│   ├─ Builds state → PROJECTOR: upsert-idempotent, rebuildable,
│   │   offset reset is routine
│   ├─ Acts on the world → SIDE-EFFECTOR: dedup by event_id first,
│   │   offsets reset only by runbook; heavy work → hand off to a
│   │   Ch 05 queue lane
│   └─ Either way: group + ack-after-processing + claim-the-crashed,
│       via the shared consumption wrapper
└─ Wire the three alerts: lag per group vs its SLO, outbox relay
    age, stream size vs memory budget
```

## قائمة المراجعة

### قائمة مراجعة التنفيذ

- [ ] Every event carries the envelope (event_id, type, version, occurred_at,
      tenant_id); payloads validate against repo-hosted typed schemas at both ends.
- [ ] All publishing goes through the transactional outbox + relay; no `xadd`/produce
      calls exist outside it (grep-enforced).
- [ ] All consumption goes through the shared group/ack/claim wrapper; no bare
      `XREAD` or auto-commit consumers outside debug tooling.
- [ ] Projectors are upsert-idempotent on natural keys; side-effectors claim a dedup
      key before any external effect.
- [ ] Streams are per domain aggregate, partition-keyed by the ordered entity, with
      MAXLEN backstops and a retention-trim task.
- [ ] Lag per group, outbox-relay age, and stream memory are exported and alerted.

### قائمة مراجعة المعمارية

- [ ] Adoption is justified by ≥2 independent consumers (or an explicit ordering/
      replay requirement) — the count appears in the ADR.
- [ ] The next-rung triggers (retention, throughput, ecosystem, org shape) are
      written, dated, and attached to the load model's review cycle.
- [ ] Retention window × event volume fits the Chapter 04 memory budget with
      headroom; the replay horizon it buys is documented.
- [ ] Each group is classified projector or side-effector with its replay policy
      recorded in the topology.
- [ ] PostgreSQL remains the system of record; anything resembling event sourcing has
      its own ADR, not a drift path.

### قائمة مراجعة الكود

- [ ] New event types: envelope + typed schema + additive evolution (or a version
      bump with a consumer migration plan) + contract test.
- [ ] New consumers: correct classification (projector/side-effector), idempotency
      mechanism named in the PR, lag SLO declared, uses the shared wrapper.
- [ ] No publishing from request handlers; producer changes touch outbox schemas,
      not transport code.
- [ ] Events describe business facts (what happened), not commands (what someone
      should do) — Stage 2's test, applied at the schema diff.
- [ ] Partition-key changes are treated as breaking contract changes and reviewed as
      such.

### قائمة مراجعة النشر

- [ ] The replay drill has passed in staging: projector broken → fixed → offset
      reset → rebuild converges → zero side effects fired (dedup verified).
- [ ] Consumer-group failover tested: kill a consumer mid-batch; verify XAUTOCLAIM
      hands its pending events to a peer, exactly-once effects hold.
- [ ] Month-end load test (the stage's running gauge) includes event-volume spikes;
      lag, relay age, and stream memory all stayed inside alerts.
- [ ] Consumer services deploy per group with the Ch 02/03 drain contract; a
      deploy-time restart never loses acknowledged position.
- [ ] Dashboards: per-group lag, relay backlog, stream size vs budget — living next
      to the Ch 04 Redis and Ch 05 queue boards, because they share an instance and
      a failure story.

## التمارين

1. **ابنِ العمود الفقري.** نفّذ المسار الكامل على Redis Streams: جدول صندوق الصادر + المرحّل، المغلف، تدفّق واحد (`invoice-events`)، ومجموعتي مستهلِكين — projector تحليلي (يُدرج upsert في جدول إيرادات-حسب-الشهر) وside-effector لتوزيع webhooks (إلغاء تكرار + إدراج في طابور الفصل 05). شغّله بحركة فواتير محاكاة وتحقّق من تقارب المجموعتين بشكل مستقل عندما تُوقَف إحداهما.
2. **شغّل تمرين إعادة التشغيل.** شحن خطأ متعمَّد في projector (إعادة عدّ إشعارات الدائن)، اترك أسبوعًا من الأحداث المحاكاة تتراكم، ثم نفّذ الاسترداد: أصلح، أعد ضبط إزاحة *projector* فقط، أعِد البناء. معايير النجاح: تتقارب التجميعات إلى القيم الصحيحة *و* يُظهر جدول إلغاء تكرار الـ webhook صفر إعادة إطلاق. زُمن إعادة البناء — هذا الرقم هو قدرتك الحقيقية على إعادة التشغيل.
3. **اقتل المستهلِك، راقب المطالبة.** شغّل مجموعة التحليلات بمستهلِكين اثنين؛ اقتل واحدًا في منتصف الدفعة (تاركًا الإدخالات المعلَّقة غير مؤكدة). راقب XAUTOCLAIM يسلّم عمله للناجي وتحقّق أن upserts جعلت إعادة التسليم غير مرئية. ثم كرّر بمستهلِك XREAD عادي ووَثّق الفرق — هذا التمرين 4 من الفصل 05، مستوى تجريد واحد أعلى.
4. **جد القسم الساخن.** امنح التدفّق مفتاح tenant_id مع مستأجر حوت اصطناعي واحد عند 40% من الحجم. قِس الإنتاجية لكل مستهلِك وتأخّر ترتيب الحوت مقارنةً بالذيل الطويل. ثم أعد المفتاح إلى invoice_id ووَثّق ما كسبته (الانتشار) وما خسرته (الترتيب لكل مستأجر) — مفاضلة مفتاح القسم، مقياسة.
5. **اكتب المذكرتين.** لنظام تعرفه: (أ) مذكرة الاعتماد — عُدّ المستهلِكين المستقلّين الفعليين لحقائقه الأساسية اليوم، واختم بـ تدفّق/قائمة انتظار/لا شيء مع إظهار الحساب؛ (ب) إذا كانت الإجابة "تدفّق"، مذكرة المحفّز — الشروط المكتوبة التي ستُجبر Kafka، كل منها مُصاغ كفجوة قدرة قابلة للقياس، مؤرّخة للمراجعة. هاتان الوثيقتان هما هذا الفصل — وهذه المرحلة — مضغوطتان إلى لبّ اتخاذ القرار.

## قراءات إضافية

- Jay Kreps — "The Log: What every software engineer should know about real-time
  data's unifying abstraction" — المقالة التي ينحدر منها النموذج الذهني لهذا الفصل؛
  أفضل شيء واحد يُقرأ في الموضوع.
- Martin Kleppmann — *Designing Data-Intensive Applications*, الفصل 11 —
  السجلّات مقابل الوسطاء، صدق مرة-واحدة-بالضبط، ودلالات معالجة التدفّق الحقيقية.
- توثيق Apache Kafka — قسم "Design" — الأقسام، مجموعات المستهلِكين،
  والاستبقاء من النظام الذي سمّاها؛ اقرأ حتى لو لم تنشر أيًا منها.
- توثيق Redis — "Redis Streams introduction" (XADD، مجموعات المستهلِكين،
  XAUTOCLAIM، PEL) — الميكانيكا وراء تنفيذ هذا الفصل.
- توثيق Debezium — موجّه أحداث صندوق الصادر ومفاهيم CDC — إلى أين يذهب
  نمط صندوق الصادر عندما يكبر.
- Martin Fowler — "What do you mean by 'Event-Driven'?" — التصنيف (إشعار،
  نقل حالة، event sourcing، CQRS) الذي يحافظ على صدق نطاق هذا الفصل.
- المرحلة 2، الفصل 07 ([العمارة المعتمدة على الأحداث](../stage-02-software-architecture/07-event-driven-architecture.md))
  — أسلوب التصميم (الأحداث مقابل الأوامر، صندوق الصادر، التناغم) الذي توجد هذه البنية التحتية لتشغيله.
