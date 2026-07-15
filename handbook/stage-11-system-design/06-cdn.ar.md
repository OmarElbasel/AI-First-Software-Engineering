# CDN

## مقدمة

كل فصل حتى الآن كان يوسّع نطاق الـorigin — مزيد من الـinstances، حالة مشتركة، queues أوسع. الـCDN
يسلك المسار الآخر: يُرتِّبُ لأن معظم الطلبات لا تصل إلى الـorigin أصلاً. الـcontent delivery network
هو أسطول من caching proxies (points of presence، PoPs) منتشرة في جميع أنحاء العالم؛ يتصل
المستخدمون بأقرب واحدة منها، والاستجابات التي يُسمح للـCDN بتخزينها مؤقتاً تُقدَّم منها — بزمن
استجابة من رقم واحد بالمللي ثانية، وبسعة لن تشبعها أبداً، دون أن تلمس آلة تدفع مقابل توسيعها.
للجزء الكثيف القراءة من أي منتج ويب — حزم JavaScript، الصور، الخطوط، صفحات التسويق، تنزيلات
PDF — هي أرخص سعة على سلّم الفصل 01، والعلاج الوحيد على السلّم الذي يُصلح الفيزياء أيضاً: لا
يوجد أي قدر من توسيع الـorigin يجعل رحلة ذهاب وإياب من سيدني إلى VPS في فرانكفورت أقصر.

المأزق الهندسي هو أن الـCDN هو cache **أنت تُهيِّئه لكنك لا تُشغِّله**، يجلس أمام
*كل شيء*، مُطيعاً للتعليمات التي تنشرها في رؤوس HTTP. هذا الانعكاس هو كامل الانضباط: الـorigin
لم يعد يقدِّم الاستجابات — بل يقدِّم الاستجابات *plus* سياسة التخزين المؤقت، وتُنفَّذ السياسة
بواسطة آلاف خوادم الـedge التي ستفعل تماماً ما تقوله الرؤوس، على نطاق واسع، بما في ذلك الشيء
الخاطئ. معظم قيمة الـCDN تتحقق من خلال ضبط رأس واحد بشكل صحيح (`Cache-Control`)، وأسوأ فئة
حوادث للـCDN — تقديم بيانات خاصة لمستخدم واحد لمستخدم آخر، من cache، في جميع أنحاء العالم —
تنتج عن ضبط نفس الرأس بشكل خاطئ.

يتناول هذا الفصل الـCDN كمكون: عقدة الرؤوس (`Cache-Control`، الـvalidators، `Vary`)، تصنيف
لفئات المحتوى والسياسة الصحيحة لكل منها، مفاتيح الـcache ومخاطر التسميم/التسرب حولها، إبطال
الصلاحية (لماذا الـfingerprinting يتفوق على الـpurge)، والمحتوى الخاص عند الـedge عبر signed
URLs. يبقى محايداً تجاه الموردين وفقاً للدستور: Cloudflare وFastly وCloudFront تختلف في
لوحات التحكم، لا في دلالات HTTP التي يعلِّمها هذا الفصل.

## لماذا يهم

- **يُزيل الحمل بدلاً من استيعابه.** الفصول 02–05 جعلت الـorigin أقوى؛ الـCDN يجعل معظم
  الطلبات لا تصل أبداً. بالنسبة لـInvoicely frontend، نحو 90% من البايتات (JS، CSS، الخطوط،
  الصور) يمكن أن تغادر الـorigin نهائياً — سعة تكلفها ملف إعدادات، لا أسطول.
- **الكمون فيزياء، والـedges فقط تُصلحه.** origin في فرانكفورت يخدم ساو باولو بزمن RTT
  يقارب 200ms قبل البايت الأول من *رابع* أصل. TTFB من PoP محلي يقارب 10ms. بالنسبة
  للمستخدمين العالميين، يفعل الـCDN أكثر للأداء المُدرَك (مقاييس الفصل 07 من المرحلة 4)
  مما يمكن لأي تحسين على الـorigin فعله.
- **إنه درعٌ ضد الارتفاعات لجانب القراءة.** صفحة التسويق التي تنتشر viralاً، رابط فاتورة
  عامة لعميل تتم مشاركتها على نطاق واسع، إعادة تنزيلات PDF في نهاية الشهر — ارتفاعات القراءة
  تهبط على الـedge، الذي تم توفيره لنطاق الإنترنت، لا نطاقك. يرى الـorigin طلباً واحداً لكل
  نافذة TTL بدلاً من واحد لكل قارئ.
- **سوء التكوين يفشل على نطاق الـcache.** توجيه `private` مفقود لا يُسرِّب استجابة واحدة — بل
  يُسرِّب dashboard أول مستخدم مُصادَق عليه إلى كل زائر لاحق لذلك الـURL حتى انتهاء TTL، من
  كل PoP خزَّنته. علَّمت المرحلة 9 فئات الثغرات؛ هذه هي التي يكون فيها المُضخِّم مدمجاً.
- **النشر والتخزين المؤقت يتفاعلان افتراضياً.** انشر HTML جديداً يُشير إلى JS جديد بينما
  JS القديم يعيش على الـedge ليوم، ويحصل المستخدمون على شاشات بيضاء — خطأ النشر الكلاسيكي يوم
  الاثنين. استراتيجية الأصول (fingerprinting) هي ما يجعل أعمار التخزين الطويلة والنشر
  المستمر متوافقين، ويجب تصميمها، لا الأمل فيها.

## النموذج الذهني

**الـCDN هو cache HTTP مطيِع بين المستخدمين والـorigin.** سلوكه هو إلى حدٍّ كبير دالة لما
يقوله الـorigin:

```
 user ──► nearest PoP ──────────────────────────► origin
           │  cache key: METHOD + host + path      │
           │  (+ query, + whatever Vary names)     │
           │                                       │
           │  HIT: serve from edge (origin never   │
           │       sees the request)               │
           │  MISS/EXPIRED: fetch from origin ─────┘
           │       obeying the response's headers:
           │
           │  Cache-Control: public, max-age=..., s-maxage=...
           │       → cacheable; how long (s-maxage = "for shared
           │         caches like me", overrides max-age at the edge)
           │  Cache-Control: private | no-store
           │       → NOT cacheable at the edge (private = browsers
           │         only; no-store = nobody)
           │  stale-while-revalidate=N
           │       → serve stale instantly, refresh in background
           │  ETag / Last-Modified
           │       → revalidation: origin answers 304 (cheap)
           │         instead of resending the body
           │  Vary: <header names>
           │       → those headers join the cache key: variants
           │         are stored separately
```

قاعدتان افتراضيتان يجب حفرهما: **الـedge يُخزِّن ما تأمره بخزْنه** — والـCDNs تطبق أيضاً
افتراضياتها الخاصة للاستجابات التي *لا* تحمل رؤوس تخزين مؤقت (بعضها يُخزِّنها!)، ولهذا
يجب أن يكون الـorigin صريحاً في كل استجابة، ولهذا فإن التطبيق الافتراضي الآمن هو
`private, no-store` مع التخزين المؤقت كـopt-in متعمَّد.

**المحتوى ليس شيئاً واحداً — السياسة تتبع الفئة.** التصنيف الذي يقرر كل رأس:

```
 CLASS                 EXAMPLES                    POLICY
 immutable versioned   /_next/static/*, hashed     public, max-age=31536000,
 assets                bundles, fonts, logo.        immutable — cache FOREVER;
                       [hash].png                   the URL changes when the
                                                    content does (fingerprint)
 semi-static shared    marketing pages, docs,       public, s-maxage=minutes..
 (same for everyone)   blog, public status/pricing  hours + stale-while-
                                                    revalidate — freshness is
                                                    a dial, not a fight
 private files         invoice PDFs, exports,       edge-cacheable ONLY behind
                       uploaded logos               signed URLs (below);
                                                    otherwise private
 per-user dynamic      dashboard, API responses,    private, no-store. The
                       anything behind auth         edge never sees it twice
```

**تُختار استراتيجية الإبطال وقت تصميم الـURL.** طريقتان لتحديث أصلٍ مخزَّن: تغيير الـURL
(fingerprinting — `app.3f9a2c.js`؛ الأصل القديم يبقى صالحاً لـHTML القديم، والـHTML الجديد يُشير
إلى الـURL الجديد، لا يوجد شيء قَدُم أو تم تنقيته)، أو تنقية الـURL (استدعاء API للـCDN يطلب
من آلاف PoPs النسيان — في نهاية المطاف). يحول الـfingerprinting إبطال الـcache — المشهور بأنه
واحد من أصعب مشكلتين — إلى مشكلة غير مشكلة بالنسبة للأصول، ولهذا يفعله كل bundler حديث. يبقى
التنقية صمام escape للمحتوى ذي الـURL القابل للتغيير (صفحة التسويق التي يجب تحديثها *الآن*)
ورافعة الطوارئ — لا آلية النشر.

**مفتاح الـcache هو حدود أمنية.** أي شيء ليس في المفتاح لا يستطيع التمييز بين الاستجابات —
لذا إذا كانت الاستجابة *تتفاوت* بحسب شيء (cookie، `Accept-Language`، tenant، حالة المصادقة)
غير مشمول في المفتاح، يتلقى المستخدمون متغيرات بعضهم البعض. هذا هو التسرب. العكس هو هجوم
التسميم: إذا كان المهاجم يستطيع التأثير في *مدخل غير مُفَتَّح* يُشكِّل الاستجابة (رأس منعكس،
معامل query مُهمَل)، يمكنه تسميم النسخة المخزَّنة التي يتلقاها الجميع. `Vary` هو كيف تُعلن
الاستجابة عن مدخلاتها الحقيقية؛ التصميم الأكثر أماناً يُبقي الاستجابات القابلة للتخزين دالة
للـURL وحده.

**المحتوى الخاص عند الـedge = capability URLs.** signed URL (تصدره التطبيق، يتحقق منها الـCDN
أو object store: path + expiry + HMAC) يحول الترخيص إلى URL محدود الوقت وغير قابل للتخمين —
بحيث يمكن للـedge تقديم PDF خاص *دون* رؤية session، لأن امتلاك الـURL هو الدليل. يبقى التطبيق
هو المُرخِّص (يقرر من يحصل على URL، وفقاً للمرحلة 3 الفصل 09 وقواعد المرحلة 9)؛ الـedge يفعل
تسليم البايتات. أعمار TTL قصيرة (دقائق)، ومدخل الـcache الخاص يعيش على الـedge فقط ما دام
URLه صالحاً.

تعريف عملي:

> **نشر CDN هو سياسة تخزين مؤقت منشورة: كل استجابة تحمل `Cache-Control` صريحاً مُختاراً
> حسب فئة المحتوى — immutable-forever للأصول ذات البصمة، تقادم محدود للصفحات المشتركة،
> `private, no-store` افتراضياً لكل شيء آخر — مع مفاتيح cache تشمل كل مدخل تتفاوت
> الاستجابة بحسبه فعلياً، الـfingerprinting (لا التنقية) كاستراتيجية إبطال، signed URLs
> حيث تلتقي الملفات الخاصة بالـedge، والـorigin محمي بحيث يكون الـedge هو الباب الوحيد.**

## مثال إنتاجي

نشر Invoicely للـCDN، مدفوع بثلاث آلام مُقاسة من اختبار الحمل في الفصل 01 وحاجة استراتيجية
واحدة:

- **أصول الـFrontend** تستحوذ على bandwidth الـorigin: كل تحميل لـdashboard يسحب نحو 2MB من
  JS وCSS والخطوط من خادم Next.js — بايتات متطابقة، آلاف المرات يومياً، من ثلاث قارات
  (الشراكة تجلب محاسبين من LatAm وAPAC).
- **ملفات PDF للفواتير تُعاد تنزيلها بكثافة**: عملاء العميل يفتحون رابط الفاتورة نفسه
  5–50 مرة (عملاء البريد الإلكتروني يجلبون مسبقاً، الهواتف تعيد الفتح). كل فتح يضرب حالياً
  الـURL الموقع مسبقاً لـobject storage من الفصل 03 — جيد للصحة، بطيء من سيدني، وكل تنزيل
  يُفوتر egress من الـorigin.
- **موقع التسويق والـdocs** يعملان على نفس الـorigin كتطبيق؛ ارتفاع حركة على منشور
  مدونة يتنافس مع استدعاءات API للمستخدمين الدافعين على نفس Nginx والـinstances.
- **استراتيجي**: طبقة الـCDN من TLS + WAF + DDoS أمام كل شيء هي أرخص طريقة لإبقاء
  حركة البريد العشوائي بعيداً عن موازن الفصل 02 بالكامل.

التصميم: CDN أمام كل شيء (اسم مضيف واحد، `app.invoicely.io`، موجه على الـedge)؛ أصول
Next.js ذات البصمة مخزَّنة immutable-forever؛ صفحات التسويق/الـdocs عند
`s-maxage=600, stale-while-revalidate=86400` (التحديثات مرئية خلال 10 دقائق، لا ينتظر
المستخدمون إعادة بناء أبداً)؛ الـAPI وHTML التطبيق بشكل صريح `private, no-store`؛ ملفات PDF
تُقدَّم من الـedge عبر CDN-signed URLs بصلاحية 15 دقيقة، يصدرها الـAPI بعد فحص الترخيص من
المرحلة 3؛ الـorigin مُقفَل بحيث حركة الـCDN فقط تصل إلى الموازن.

## بنية المجلدات

عمل الـCDN هو كود سياسة، لا خدمات جديدة — رؤوس في المكانين اللذين تُولَّد فيهما الاستجابات،
بالإضافة إلى إعدادات الـedge:

```
frontend/
└── next.config.ts              # headers() for marketing/docs routes
                                #   (s-maxage + SWR); /_next/static is
                                #   fingerprinted + immutable by the
                                #   framework — verify, don't reinvent
app/
├── core/
│   └── http_cache.py           # THE policy module: the no-store
│                               #   default middleware + the explicit
│                               #   cacheable() opt-in — one reviewable
│                               #   home for every caching decision
├── files/
│   └── signed_urls.py          # CDN-signed URL issuance for private
│                               #   files (replaces raw presigned-S3
│                               #   links from Ch 03 in user-facing
│                               #   flows)
infrastructure/
└── cdn/
    ├── config.md               # vendor config as documentation: zones,
    │                           #   cache rules, origin-shield choice,
    │                           #   the origin-lock secret — reviewable
    │                           #   even when the vendor UI isn't
    └── purge.sh                # the escape hatch, scripted and logged
                                #   — never a dashboard click nobody
                                #   can audit later
```

لماذا `http_cache.py` واحد: رؤوس التخزين المؤقت المبعثرة عبر الـendpoints هي كيف ينتهي الأمر
بـendpoint واحد إلى `public` عن طريق النسخ واللصق. السياسة كـmodule تعني أن grep على "ماذا
يمكن للـedge تخزينه؟" له إجابة واحدة، ومراجعة الكود تحرس باباً واحداً.

## التنفيذ

الافتراضي للتطبيق — لا شيء قابل للتخزين على الـedge ما لم يُشترَك صراحةً:

```python
# app/core/http_cache.py
from fastapi import Request, Response

CACHEABLE_DEFAULT = "private, no-store"

async def cache_headers_middleware(request: Request, call_next):
    """Every response leaves with EXPLICIT cache policy. Endpoints that
    set their own Cache-Control keep it; everything else is private by
    default — an unheadered response at a CDN is a coin flip we don't
    take."""
    response: Response = await call_next(request)
    response.headers.setdefault("Cache-Control", CACHEABLE_DEFAULT)
    return response


def cacheable(*, s_maxage: int, swr: int = 0, vary: tuple[str, ...] = ()):
    """The opt-in for the few public, same-for-everyone endpoints.
    Usage: return cacheable(s_maxage=300)(response). Anything using
    this MUST be auth-free and user-independent — that invariant is
    what code review checks at every call site."""
    def apply(response: Response) -> Response:
        value = f"public, max-age=60, s-maxage={s_maxage}"
        if swr:
            value += f", stale-while-revalidate={swr}"
        response.headers["Cache-Control"] = value
        if vary:
            response.headers["Vary"] = ", ".join(vary)
        return response
    return apply
```

Next.js — تحقَّق من قصة الأصول في الـframework، أضف السياسة للصفحات المشتركة:

```ts
// next.config.ts (excerpt)
export default {
  async headers() {
    return [
      {
        // marketing + docs: same for everyone, updated occasionally.
        // 10-minute edge freshness; a day of serve-stale keeps users
        // fast (and the site up) while the edge revalidates.
        source: "/(pricing|docs|blog)/:path*",
        headers: [{
          key: "Cache-Control",
          value: "public, s-maxage=600, stale-while-revalidate=86400",
        }],
      },
      // /_next/static/* ships fingerprinted with
      // "public, max-age=31536000, immutable" by the framework.
      // App pages (dashboard) are dynamic and remain private —
      // confirmed in the deploy checklist, not assumed.
    ];
  },
};
```

ملفات PDF الخاصة على الـedge — التطبيق يُرخِّص، والـURL يحمل الدليل:

```python
# app/files/signed_urls.py
import hashlib
import hmac
import time

from app.core.config import settings

def signed_cdn_url(path: str, ttl_seconds: int = 900) -> str:
    """CDN-verified signed URL (vendor-neutral HMAC scheme; every CDN
    offers an equivalent). The edge checks expiry+signature and serves
    the object from cache or object storage; no session ever reaches
    the edge. WHO may get a URL was already decided by the caller —
    this function only mints proof, it never authorizes."""
    expires = int(time.time()) + ttl_seconds
    payload = f"{path}:{expires}"
    sig = hmac.new(
        settings.cdn_signing_key.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()
    return f"https://cdn.invoicely.io{path}?exp={expires}&sig={sig}"
```

```python
# app/invoicing/api.py (excerpt) — the endpoint that mints it
@router.get("/invoices/{invoice_id}/pdf-link")
async def invoice_pdf_link(invoice_id: UUID, user: CurrentUser) -> dict:
    invoice = await invoices.get_authorized(invoice_id, user)  # St.9: IDOR check
    return {"url": signed_cdn_url(f"/pdfs/{invoice.pdf_key}"), "expires_in": 900}
```

حماية الـorigin — يجب أن يكون الـedge هو الباب الوحيد، وإلا فكل رأس أعلاه استشاري:

```nginx
# Ch 02's balancer, one addition: requests not carrying the CDN's
# secret header (set by the CDN on origin fetches) are refused.
# Without this, "private, no-store" can be bypassed by talking to
# the origin directly — and so can the CDN's WAF and rate limits.
if ($http_x_origin_key != "REPLACED_BY_DEPLOY_SECRET") { return 403; }
```

## القرارات الهندسية

### ما الذي يوضع خلف الـCDN — الأصول فقط، أم كل شيء؟

كل شيء، مع السياسة تقوم بالتمييز. توجيه `/static` فقط عبر الـCDN يترك الـorigin مكشوفاً
للباقي ويُقسِّم TLS/DNS/WAF عبر بابين أماميين. اسم مضيف واحد موجه على الـedge مع `Cache-Control`
حسب الفئة يحصل على حماية كاملة ويُبقي قرارات التخزين في الكود (الرؤوس) بدلاً من طوبولوجيا
التوجيه. التكلفة هي أن *كل* استجابة من رؤوسها مهمة الآن — وهذا middleware الـno-store الافتراضي
موجود لجعل ذلك آمناً.

### TTL والتقادم لكل فئة — ما هو القرص؟

بالنسبة للأصول ذات البصمة لا يوجد قرص: forever + `immutable` هو ببساطة صحيح، لأن التقادم
مستحيل عندما تعني تغييرات المحتوى تغييرات الـURL. بالنسبة للصفحات المشتركة القرص هو
`s-maxage` (ما مدى قِدَم نسخة *أحدث* زائر؟) بالإضافة إلى `stale-while-revalidate` (إلى متى
يمكن للـedge الاستمرار في الخدمة أثناء التحديث؟) — يُضبط من معنى المحتوى: تغييرات التسويق
نادرة لكن يجب أن تهبط خلال دقائق من الإطلاق (600s)؛ الـdocs يتسامح مع أكثر؛ صفحة الحالة
العامة تتسامح مع *أقل* (30s — وظيفتها كلها هي الحداثة). يبقى الافتراضي للـAPI هو no-store:
البيانات لكل مستخدم ليس لها TTL مشترك آمن، والتخزين الدقيق micro-caching للاستجابات
المُصادَق عليها هو تسرب بكرونومتر.

### بصمة أم تنقية؟

بصِّم كل ما يمكن بصمته (الـbundlers تفعله مجاناً)، واعتبر التنقية شيئين فقط: رافعة التحديث
لـURLs القابلة للتغيير بأمانة (HTML التسويقي — تنقية عند النشر، مُبرمَجة)، ورافعة الحوادث
(شيء خاطئ تم تخزينه — purge-all والتحقيق). ليست أبداً آلية النشر: النشر القائم على التنقية
يتسابق (التنقيات العالمية تستغرق ثوانٍ إلى دقائق للانتشار بينما تُقدَّم أصول قديمة/جديدة
مختلطة)، يضرب حدود معدل المورد، ويُقرِن كل إصدار بكون API الـCDN فعّالاً. تصميم البصمة ليس
به سباق بالبناء: HTML قديم → أصول قديمة (لا تزال مخزَّنة)؛ HTML جديد → أصول جديدة.

### Signed URLs أم proxy-through-app للملفات الخاصة؟

signed URLs، لأي شيء أكبر من استجابة JSON: التطبيق يقوم بالترخيص مرة واحدة ويصدر الدليل؛
البايتات تتدفق من الـedge إلى المستخدم دون شغل اتصال instance تطبيق، وworker، وbandwidth لمدة
تنزيل الجوال (المرحلة 3 الفصل 09 قدَّمت هذا الحجة ضد proxying من object storage؛ الـCDN يمددها
إلى الـedge). يبقى الـproxying عبر التطبيق صحيحاً عندما يجب *إعادة فحص* الترخيص في وقت القراءة
لكل byte-range أو الاستجابة مُخصصة. المقبض الذي يهم: الانتهاء. 15 دقيقة تغطي prefetch عميل
البريد الإلكتروني وإعادة الفتح؛ signed URL مدته 24 ساعة هو تسرب قابل للمشاركة بفتيل طويل —
أي شخص يحمل الرابط *هو* مُرخَّص حتى الانتهاء، لذا عالج طول TTL كقرار ترخيص، لا قرار راحة.

### أي مورد — وما هو القابل للنقل فعلياً؟

دلالات الفصل (Cache-Control، Vary، الـvalidators، signed URLs، قفل الـorigin) هي HTTP وقابلة
للنقل عبر Cloudflare/CloudFront/Fastly/bunny — اختر على المحاور المملة: السعر لكل TB، تغطية
PoP حيث *مستخدموك*، سرعة التنقية إذا كنت تعتمد عليها، وما إذا كانت طبقة WAF/bot تستبدل
أدوات ستُشغِّلها خلاف ذلك. ما *ليس* قابلاً للنقل: قواعد الـcache الخاصة بالمورد، edge
functions/workers، والإعدادات الموجودة فقط في لوحة التحكم — ولهذا `infrastructure/cdn/config.md`
يوثِّق كل إعداد: الإعدادات التي توجد فقط في واجهة المورد هي pet server المرحلة 7، نُقلت
إلى سحابة شخص آخر.

## المقايضات

| Choice | You gain | You pay |
|---|---|---|
| CDN in front of everything | One door: WAF/TLS/DDoS coverage, policy in headers | Every response's headers are now load-bearing; the no-store default is mandatory |
| CDN for assets only | Small blast radius, minimal header audit | Origin still exposed; two front doors to operate; dynamic spikes unabsorbed |
| Long s-maxage + SWR on pages | Users never wait; origin barely queried; spikes flattened | Updates propagate on a delay you chose; emergency changes need purge |
| Short TTLs everywhere | Freshness with no purge discipline | Most of the offload evaporates; origin stays in the read path |
| Fingerprinted assets, immutable | Zero staleness, zero purges, deploy-safe by construction | Requires build discipline (bundler-managed URLs; no hand-edited assets) |
| Purge-driven updates | Works for honest mutable URLs | Propagation races, rate limits, CDN API coupling; unusable as deploy strategy |
| Signed URLs for private files | Edge-speed private downloads; app instances freed | URL possession = authorization until expiry; TTL is a security dial |
| Proxying private files | Re-auth on every read | App bandwidth/connections consumed per download; no edge help |
| Micro-caching "safe" API GETs | Origin relief on hot public endpoints | One personalization slip = cross-user leak; needs airtight review |

## الأخطاء الشائعة

- **`public` (أو لا شيء) على استجابات مُصادَق عليها.** كارثة الـCDN الكنسيّة: استجابة
  لكل مستخدم مخزَّنة على الـedge ومُقدَّمة لمُقدِّم الطلب التالي لذلك الـURL. الأسباب: تمريرة
  "أضف رؤوس التخزين المؤقت" شاملة، أو افتراضي framework، أو استجابات *بدون رؤوس* تلتقي
  بـCDN يخزِّن افتراضياً. middleware الـno-store الافتراضي بالإضافة إلى قائمة opt-in صريحة
  هو الإصلاح الهيكلي.
- **أعمار TTL طويلة على أصول غير مُبصَّمة.** `app.js` مخزَّن لأسبوع يلتقي نشراً يغيره ←
  يحمل المستخدمون الـbundle القديم ضد HTML وAPIs جديدة: شاشات بيضاء، أخطاء hydration، تذاكر
  دعم "امسح ذاكرة التخزين المؤقت لديك". يجعل الـfingerprinting هذا مستحيلاً؛ `?v=2` يدوياً
  يعيد إنشاءه في أول مرة ينسى فيها شخص.
- **`Vary` مفقود على مدخلات استجابة حقيقية.** الـendpoint يقدِّم JSON أو CSV بحسب `Accept`،
  أو محتوى مُحَلْى بحسب `Accept-Language`، مخزَّن بدون `Vary` — متغير مُقدِّم الطلب الأول
  يصبح متغير الجميع. وكذلك توأمها: `Vary: Cookie` على موقع بملفات تعريف ارتباط للجلسات، مما
  يُفتِّت الـcache إلى مدخلات لكل مستخدم (معدل إصابة ~0) — عادةً علامة على أن الاستجابة
  لا يجب تخزينها على الـedge أصلاً.
- **تسميم الـcache عبر مدخلات غير مُفَتَّحة.** تعكس الاستجابة رأساً (`X-Forwarded-Host` في
  URLs مطلقة، origin مُكرَّر في CORS) غير موجود في مفتاح الـcache: يرسل المهاجم طلباً مصمَّماً
  واحداً، تُخزَّن الاستجابة المسمومة، ويقدِّم الـedge payload المهاجم للجميع. يجب أن تكون
  الاستجابات القابلة للتخزين دوال على مفتاح الـcache الخاص بها — لا شيء آخر.
- **الـorigin غير المُقفَل.** CDN مُهيَّأ، DNS مُحوَّل، لكن الـorigin لا يزال يجيب أي شخص يجد
  عنوان IP الخاص به (سجلات شفافية الشهادات تجعل ذلك تافهاً): كل قاعدة WAF، وحد معدل،
  ودرع مخزَّن اختياري للمهاجمين. رأس قفل الـorigin (أو allowlist لعناوين IP، أو mTLS) جزء
  من النشر، لا فكرة متأخرة للتقوية.
- **تصديق معدل إصابة لوحة التحكم.** معدل إصابة عالمي 95% هو فعلياً 99.9% على الخطوط و8%
  على الـendpoint الذي أضفت الـCDN من أجله. معدل الإصابة مقياس لكل فئة محتوى؛ قسه لكل
  route قبل إعلان النصر (ومعدل طلبات الـorigin هو الرقم الذي يدفع الفواتير).
- **الاختبار عبر الـcache.** سلوكيات الـstaging تم التحقق منها مقابل edge دافئ بالفعل،
  أو تم "إصلاح" QA بواسطة الـCDN الذي يقدِّم بناء الأمس. اختبر التخزين المؤقت نفسه
  عمداً (curl مع رؤوس cache-status، وفقاً للتمارين) واحتفظ بمسار cache-busting للتحقق من
  سلوك الـorigin.

## أخطاء الذكاء الاصطناعي

### Claude Code: الرأس العام على البيانات الخاصة

عند طلب "تحسين أداء API بالتخزين المؤقت"، يضيف Claude Code رؤوس `Cache-Control` عبر
الـendpoints في تمريرة واحدة متحمسة — بما في ذلك `public, max-age=300` على استجابات
لكل مستخدم: قائمة الفواتير، ملخص الـdashboard، `/me`. لا شيء يفشل في التطوير (لا يوجد
shared cache يعمل هناك) أو في الاختبارات (كل واحدة تعمل معزولة). يُفعَّل الخطأ فقط عندما
يصل الـCDN، وعندها تصبح قائمة فواتير المستخدم A هي الاستجابة المخزَّنة للمستخدم B — فئة
الحادث بالضبط التي يسمّيها هذا الفصل كارثية، مُدخَلة بواسطة diff بدا كل سطر فيه مكسب أداء.

**الاكتشاف:** `public` أو أي `s-maxage` على route يقرأ سياق المصادقة (الاعتماد على المستخدم
الحالي، session، أو tenant)؛ رؤوس تخزين مؤقت تُضاف بالجملة بدلاً من per endpoint مع تبرير
مُعلَن. **الإصلاح:** الافتراضي الهيكلي من هذا الفصل — middleware يفرض `private, no-store`،
المساعد `cacheable()` هو الـopt-in الوحيد، وقاعدة المراجعة لكل call site هي سؤال واحد:
"هل هذه الاستجابة متطابقة لكل مستخدم على الأرض؟"

### GPT: النشر عن طريق التنقية

اسأل GPT كيف يتعامل مع تخزين CDN المؤقت مع عمليات نشر متكررة والإجابة المعتادة هي خطوة
إبطال في CI: "بعد النشر، انقِّ cache الـCDN" — أحياناً purge-all، أحياناً قائمة مسارات،
تُقدَّم كممارسة قياسية. إنه يعكس التصميم الصحيح: مع الأصول ذات البصمة لا يوجد شيء لتنقيته
(الـURLs القديمة تبقى صالحة، الـURLs الجديدة جديدة)، بينما ترث النشر القائمة على التنقية
سباقات الانتشار (مستخدمون في جميع أنحاء العالم يواجهون خليطاً قديماً/جديداً لنافذة التنقية)،
وحدود معدل المورد (النشر رقم 12 اليوم يحصل على throttling)، واعتمادية صلبة لكل إصدار على
API الـcontrol-plane الخاص بالـCDN.

**الاكتشاف:** استدعاءات purge/invalidation في خطوط نشر لمحتوى يمكن بصمته؛ "إبطال عند النشر"
مُقدَّم كاستراتيجية الأصول؛ versioning بـ`?v=` مقترح بجانبها. **الإصلاح:** الـfingerprinting هي
استراتيجية النشر؛ التنقية تبقى فقط كرافعة مُبرمَجة لـURLs القابلة للتغيير بأمانة (النشر
التسويقي) والحوادث. في خط النشر، الخطوة الصحيحة للـCDN هي *لا شيء*.

### Cursor: التفاوض على محتوى لا يستطيع مفتاح الـcache رؤيته

عند إضافة دعم locale لصفحة التسويق العامة، يُكمل Cursor تلقائياً النمط القياسي — قراءة
`Accept-Language` (أو cookie `currency`)، عرض أسعار مُحَلْية — مباشرة في route يحمل بالفعل
`public, s-maxage=600`. الإكمال صحيح محلياً والـdiff لا يلمس سطر التخزين المؤقت على الإطلاق،
فلا شيء يُعلِّم: الاستجابة الآن تتفاوت بحسب مدخل لا يتضمنه مفتاح الـcache. أول زائر ألماني
بعد كل انتهاء TTL يحدد لغة الصفحة للعالم؛ الدعم يحصل على "موقعك يعرض اليورو" من تكساس،
بشكل متقطع، غير قابل للتكرار — توقيع كل خطأ متغير غير مُفَتَّح.

**الاكتشاف:** قراءات رؤوس الطلب أو ملفات تعريف الارتباط (`Accept-Language`، العملة،
علامات A/B، ملفات تعريف الارتباط للميزات) تظهر في handlers/pages استجاباتها قابلة للتخزين
على الـedge؛ `Vary` غائب من نفس الـdiff. **الإصلاح:** ثابت المراجعة — *أي مدخل جديد لاستجابة
قابلة للتخزين يجب أن يظهر في نفس الـdiff كإما إدخال `Vary`، أو قطعة URL
(`/de/pricing` — عادةً الإجابة الصحيحة: تُبقي معدلات الإصابة عالية وقابلة للمشاركة)، أو
إزالة قابلية التخزين.* مساعدة هيكلية: أبقِ قائمة routes القابلة للتخزين قصيرة وفي مكان
واحد، بحيث "هذا الـroute مخزَّن" مرئي من الكود الذي يتم إكماله.

## أفضل الممارسات

- **الافتراضي مُغلق، يُفتح لكل route.** `private, no-store` من الـmiddleware؛ `cacheable()` واحد
  كـopt-in مع قائمة call-sites قابلة للـgrep؛ مراجعة PR تسأل سؤال "متطابق للجميع" في كل
  موقع جديد. هذا الهيكل الواحد يمنع فئة التسرب بالكامل.
- **دع الـbundler يمتلك URLs الأصول.** الـfingerprinting مجاني من Next.js/Vite — الممارسة
  هي *عدم هزيمته*: لا ملفات موضوعة يدوياً في مجلدات static، لا قواعد CDN تجرِّد query
  strings أو تعيد كتابة مسارات الأصول، تحقق أن رأس `immutable` يصل إلى الإنتاج.
- **اختر أعمار TTL من معنى المحتوى، واكتبها.** جدول فئات المحتوى من النموذج الذهني، مُنشَأ
  لمنتجك، يعيش في `infrastructure/cdn/config.md` بجملة تبرير لكل فئة — القطعة القابلة
  للمراجعة التي توقف انجراف أعمار TTL بالنسخ واللصق.
- **وقِّع قصيراً، أصدر بسخاء.** URLs الملفات الخاصة عند ~15 دقيقة؛ الـendpoints تعيد الإصدار
  بحرية (رابط انتهى منتصف الاجتماع يُعاد جلبه في استدعاء واحد). طول الانتهاء هو مدة
  الترخيص — عالج التمديدات كقرارات أمنية.
- **أقفل الـorigin من اليوم الأول واختبر القفل.** فحص 403-بدون-سر، بالإضافة إلى probe
  شهري (curl لعنوان IP الـorigin مباشرة) بنفس روح تمرين القتل في الفصل 02. الـorigin الذي
  يجيب الغرباء يجعل الـCDN تزيينياً.
- **راقب معدل الإصابة لكل فئة وتفريغ الـorigin.** لوحات تحكم: معدل إصابة الـedge حسب فئة
  الـroute، معدل طلبات الـorigin (العدد قبل/بعد)، بايتات egress الـorigin، واستدعاءات API
  التنقية (سجل تدقيق — كل تنقية لها مؤلف وسبب).
- **تحقق من سلوك الـcache كجزء من QA.** سكربت smoke يجلب كل فئة محتوى مرتين ويُثبت رأس
  cache-status (HIT/MISS/BYPASS كما هو متوقع) — يعمل في الـstaging مقابل منطقة CDN حقيقية،
  يلتقط التخزين الزائد والناقص قبل أن يفعل المستخدمون ذلك.

## الأنماط المضادة

- **نشر تحويل DNS.** توجيه DNS إلى CDN بإعدادات افتراضية وبدون تدقيق للرؤوس — وراثة
  استدلالات التخزين-الافتراضي للمورد عبر تطبيق مليء باستجابات مُصادَق عليها بدون رؤوس.
  ترتيب النشر: تدقيق الرؤوس → قفل الـorigin → سكربت smoke أخضر → ثم DNS.
- **تخزين غلاف التطبيق المُسجَّل فيه "للسرعة".** تخزين edge لـHTML الـdashboard أو استجابات
  API لكل مستخدم بأعمار TTL صغيرة، بحجة أن "30 ثانية لا يمكن أن تضر". نافذة 30 ثانية
  بمعدلات طلب الإنتاج هي آلاف الاستجابات المُقدَّمة بالتبادل. المحتوى المُخصص يحصل على
  توصيل edge (إنهاء TLS، التوجيه) — أبداً تخزين edge.
- **كسر الـcache المُصنَّع يدوياً.** `script.js?v=2` يرفعه البشر: يُنسى عند النشر الحرج،
  غير متوافق مع الإصدارات المتوازية، وتهزمه إعدادات CDN تتجاهل query strings. الـbundler
  حل هذا بالفعل؛ استخدم مُخرجاته.
- **CDN كعباءة لـorigin بطيء.** صفحة مدتها 6 ثوانٍ مخفية خلف TTL طويل — p99 (كل انتهاء TTL،
  كل مستخدم cache-busting) لا يزال يأكل الـ6 ثوانٍ كاملة، وعاصفة الـmiss بعد أي تنقية هي
  انقطاع. أصلح الـorigin (الفصول 01–05)؛ خزِّن الشيء المُصلَح.
- **إعدادات تعيش فقط في لوحة تحكم المورد.** قواعد cache، redirects، ومنطق edge متراكم
  بالنقر — غير قابل للمراجعة، غير قابل للتكرار، غير قابل للـdiffing، وبمفارقة حساب واحدة
  من الاختفاء. الإعدادات-كتوثيق (أو Terraform provider للمورد) هو انضباط المرحلة 7 مُطبَّق
  على البنية التحتية المُستأجَرة.
- **Purge-all كمنعكس.** كل خطأ محتوى يُجاب عليه بتنقية عالمية — وهو "يعمل" (يُخفي أخطاء
  المتغير غير المُفَتَّح والتسميم) بينما يفرض عاصفة miss كاملة على الـorigin. التنقيات
  تعالج الأعراض؛ مفتاح الـcache أو الرؤوس كانت خاطئة، ويجب أن يقول postmortem أيهما.

## شجرة القرار

```
A response/asset meets the CDN — set its policy:
│
├─ Is the response identical for every user on earth?
│   ├─ NO →
│   │   ├─ Private FILE (PDF, export, upload) that's heavy or hot?
│   │   │   → signed URL (app authorizes, mints short-expiry proof;
│   │   │     edge delivers). Expiry = authorization duration.
│   │   ├─ Needs re-auth per read / personalized body →
│   │   │   private, no-store; app serves it (the default path)
│   │   └─ "But it's only slightly per-user" → still no-store.
│   │       There is no safe shared TTL for per-user data.
│   └─ YES ↓
├─ Does its URL change when its content changes (fingerprinted)?
│   ├─ YES → public, max-age=31536000, immutable. Done forever.
│   └─ NO ↓
├─ Mutable-URL shared content (pages, docs, public JSON):
│   ├─ How stale may the newest visitor's copy be? → s-maxage
│   ├─ May the edge serve stale while refreshing? → + SWR (usually yes)
│   ├─ Does the response vary by ANY header/cookie input?
│   │   ├─ Put it in the URL (/de/pricing) — best hit rate, shareable
│   │   ├─ Or Vary on it — correct, fragments the cache
│   │   └─ Or drop cacheability — when variance is per-user anyway
│   └─ Update mechanism: publish-triggered scripted purge (logged)
└─ Rollout invariants (any content class):
    ├─ Origin locked: only edge traffic reaches the balancer
    ├─ No response leaves the origin without explicit Cache-Control
    └─ Smoke script asserts HIT/MISS/BYPASS per class in staging
```

## قائمة المراجعة

### قائمة مراجعة التنفيذ

- [ ] middleware الـno-store الافتراضي نشط؛ `cacheable()` هو الـopt-in الوحيد وكل call
      site خالٍ من المصادقة ومستقل عن المستخدم.
- [ ] الأصول ذات البصمة تُشحن بـ`public, max-age=31536000, immutable` وخط أنابيب البصمة
      مملوك للـbundler من النهاية إلى النهاية (تم التحقق في رؤوس الإنتاج، لا مفترض).
- [ ] الصفحات المشتركة تحمل `s-maxage` + `stale-while-revalidate` مناسباً للفئة وفقاً
      لجدول فئات المحتوى الموثَّق.
- [ ] كل مدخل تتفاوت الاستجابة القابلة للتخزين بحسبه موجود في URLها أو رأس `Vary` —
      تم فحصه لكل route.
- [ ] إصدار signed-URL: الترخيص يسبق الإصدار؛ الانتهاء ≤ 15 دقيقة ما لم يُبرَّر؛ مفتاح
      التوقيع في إدارة الأسرار (المرحلة 9)، يُدوَّر وفق جدول.
- [ ] قفل الـorigin مُنفَّذ عند الموازن (رأس سر / allowlist / mTLS) ومغطى بـprobe متكرر
      مباشر للـorigin.

### قائمة مراجعة البنية

- [ ] جدول فئات المحتوى مكتوب لهذا المنتج: الفئات، الأمثلة، السياسة، التبرير — في
      الـrepo، لا في لوحة تحكم المورد.
- [ ] استراتيجية الإبطال بصمة-أولاً؛ التنقية محدودة النطاق لـURLs القابلة للتغيير
      والحوادث، مُبرمَجة ومسجلة بمؤلف + سبب.
- [ ] إعدادات مورد CDN موثَّقة/مُصدَّرة في الـrepo؛ حدود القابلية للنقل (edge functions،
      قواعد المورد) معروفة ومُصغَّرة.
- [ ] معدل إصابة لكل فئة، معدل طلبات الـorigin، وegress الـorigin على لوحات التحكم؛
      إنفاق الـCDN له رقم بجوار سعة الـorigin التي استبدلها.
- [ ] قصة الفشل محددة: انقطاع CDN → DNS fallback؟ سعة الـorigin للحمل غير المحمي؟ (عادةً:
      اقبل SLA المورد، وثِّق القرار.)

### قائمة مراجعة الكود

- [ ] أي diff يضيف `public`/`s-maxage` يجيب عن "متطابق لكل مستخدم؟" في PR — المراجع
      يتحقق من اعتماد المصادقة في الـroute.
- [ ] أي قراءة لرأس طلب/cookie جديدة في route قابل للتخزين تصل مع `Vary`، أو قطعة URL،
      أو إزالة قابلية التخزين — في نفس الـdiff.
- [ ] لا مدخلات طلب منعكسة (رؤوس host، أصول، أصداء query) في أجسام استجابات قابلة
      للتخزين — فحص التسميم.
- [ ] تغييرات TTL لـsigned-URL تُعامل كتغييرات ترخيص وتُراجَع كذلك.
- [ ] لا أصول مُنسَّخة يدوياً (`?v=`) أو ملفات تتجاوز خط أنابيب بصمة الـbundler.

### قائمة مراجعة النشر

- [ ] ترتيب النشر محفوظ: تدقيق الرؤوس → قفل الـorigin → smoke الـstaging (HIT/MISS/BYPASS
      لكل فئة مُثَبَّت) → تحويل DNS — مع إبقاء سكربت الـsmoke كفحص دائم بعد النشر.
- [ ] خط النشر لا يحتوي خطوة تنقية للأصول ذات البصمة؛ نشر التسويق يُفعِّل تنقيته
      المحدودة النطاق، المُسجَّلة.
- [ ] تم التحقق من نشر تحت واقع الـcache: HTML قديم + أصول قديمة وHTML جديد + أصول جديدة
      كلاهما يعمل خلال نافذة التداخل.
- [ ] probe مباشر للـorigin، لوحات تحكم معدل الإصابة لكل فئة، وسجل تدقيق التنقية حية
      قبل الحركة.
- [ ] اختبار حمل نهاية الشهر (الفصل 01، الممتد في كل فصل) يعمل الآن عبر الـedge ويُبلِّغ
      عن تفريغ الـorigin كسطر نتيجة.

## التمارين

1. **تدقيق قبل التخزين.** مقابل تطبيقك الحالي (لا CDN بعد)، اعمل curl لكل فئة route رئيسية
   وسجِّل كل `Cache-Control` (أو غيابه). صنِّف كل route في جدول فئات المحتوى وأنتج
   قائمة الفجوات: استجابات بدون رؤوس، routes لكل مستخدم ستتسرب تحت CDN بخزن-افتراضي،
   أصول بدون بصمات. هذه القائمة هي تقدير العمل الحقيقي للنشر.
2. **أعد إنتاج التسرب، ثم اجعله مستحيلاً هيكلياً.** في الـstaging مع caching proxy محلي
   (nginx `proxy_cache` يقف مكان الـCDN)، اضبط `public, max-age=60` على endpoint مُصادَق عليه.
   سجِّل الدخول كمستخدم A، اضربه، ثم كمستخدم B — لاحظ بيانات A تُقدَّم لـB. ثبِّت middleware
   الـno-store الافتراضي وopt-in الـ`cacheable()`، أعد التشغيل، واحتفظ بالزوج الفاشل-ثم-الناجح
   كاختبار انحدار للـmiddleware.
3. **سابق النشر.** مع أصول *غير مُبصَّمة* بعمر TTL طويل في cache الـstaging، انشر تغييرا
   حيث HTML جديد يتطلب JS جديد. وثق الانكسار (شاشة بيضاء/أخطاء console حيث JS القديم يلتقي
   ترميزاً جديداً). انتقل إلى مُخرج الـbundler ذو البصمة، كرر النشر، وتحقق أن نافذة التداخل
   نظيفة في الاتجاهين. اكتب postmortem من فقرتين — إنه حجة الـfingerprinting بكلمات حادثك
   الخاص.
4. **قدِّم PDF خاصاً من الـedge.** نفِّذ `signed_cdn_url()` ضد CDN الخاص بك أو HMAC-verifying
   proxy محلي: endpoint مُرخَّص يصدر URL مدته 15 دقيقة، الـedge يتحقق من التوقيع والانتهاء،
   URLs المنتهية تحصل على 403 وتدفق إعادة إصدار نظيف في الـUI. اختبر الحمل لمسار التنزيل
   وقارن شغل اتصال instance التطبيق مقابل خط الأساس proxy-through-app من الفصل 03.
5. **جد المتغير غير المُفَتَّح.** أضف عرض locale (عبر `Accept-Language`) لصفحة staging مخزَّنة
   *بدون* `Vary` ووضِّح التلوث عبر اللغات بملفي curl. أصلحه بالطرق الثلاث — `Vary`، قطعة
   URL، إزالة التخزين — قس معدلات الإصابة لكل منها، واكتب ثلاث جمل عن أيها ستشحن ولماذا.
   ثم تحقق من تطبيقك الحقيقي لنفس الفئة: اعمل grep على routes القابلة للتخزين لقراءات
   الرؤوس/ملفات تعريف الارتباط.

## قراءات إضافية

- RFC 9111 — *HTTP Caching* — المصدر المعياري لكل توجيه يستخدمه هذا الفصل؛ أقصر وأكثر
  قابلية للقراءة من سمعته.
- MDN — "HTTP caching" ومرجع `Cache-Control` — نسخة المهندس العامل من RFC.
- James Kettle (PortSwigger) — "Practical Web Cache Poisoning" وتواليها — أدبيات الهجوم
  وراء انضباط مفتاح الـcache في هذا الفصل؛ قراءة مطلوبة قبل تخزين أي شيء يعكس مدخلات.
- web.dev — "Love your cache" / أفضل ممارسات التخزين المؤقت — استراتيجية بصمة الأصول كما
  ينفذها عالم الـframework.
- وثائق CDN الخاص بك حول: مفاتيح الـcache، signed URLs، وحماية الـorigin — الأماكن الثلاثة
  التي يختلف فيها سلوك المورد حقاً؛ اقرأ مقابل دلالات هذا الفصل.
- وثائق Next.js — "Caching" — ما يفعله الـframework بالفعل (أصول static غير قابلة للتغيير،
  ISR) بحيث تُهيِّئ حوله لا ضده.
- المرحلة 3، الفصل 09 ([File Storage](../stage-03-backend-engineering/09-file-storage-and-email.md))
  والمرحلة 4، الفصل 07 ([Frontend Performance](../stage-04-frontend-engineering/07-frontend-performance.md))
  — أساسيات التخزين والأداء التي يمددها هذا الفصل إلى الـedge.
