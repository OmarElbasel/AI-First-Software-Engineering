# Nginx، الـ Reverse Proxy، النطاقات و TLS

## مقدمة

بين تطبيقك والإنترنت توجد مهمة واحدة: استقبال سيل غير موثوق به من الطلبات العامة على
نطاق حقيقي عبر اتصالات مشفّرة، وتسليمها بأمان إلى خدمات لا ينبغي أن تواجه الإنترنت
مباشرةً أبدًا. تلك المهمة هي الـ reverse proxy، و Nginx هو حصان العمل الذي يقوم بها
لنسبة ضخمة من الويب. يُنهي Nginx TLS (بحيث يتحدث تطبيقك عبر HTTP عادي داخليًا بينما
يحصل المستخدمون على HTTPS)، ويُوجّه الطلبات إلى الـ backend المناسب، ويخدم الأصول
الثابتة بكفاءة، ويُعيّن مهلات وحدود حجم تحمي تطبيقك من إساءة الاستخدام، ويقدّم بابًا
أماميًا واحدًا مُحَصَّنًا على المنافذ 80 و 443. يربط هذا الفصل ثلاثة مواضيع في
المنهج هي في الحقيقة فكرة واحدة — **كشف التطبيق للإنترنت بشكل آمن** — وهو الـ proxy،
والعنوان (النطاقات/DNS)، والتشفير (TLS/SSL عبر Let's Encrypt).

الفكرة الأهم على الإطلاق: **الـ reverse proxy هو نقطة الدخول العامة الوحيدة التي
تفصل بين "كيف يصل العالم إليك" (نطاق واحد، HTTPS، المنفذ 443) و"كيفية هيكلة خدماتك"
(عدة خدمات داخلية على منافذ خاصة) — وهو المكان الذي تنتمي إليه TLS والتوجيه والمهلات
والحدود ورؤوس الأمان، وليس في التطبيق.** لا ينبغي أن يُنهي تطبيق FastAPI الخاص بك
TLS، أو يحلل `X-Forwarded-For`، أو يفرض حدًا لحجم الطلب، أو يخدم الملفات الثابتة —
هذه مخاوف تتعلق بالحافة، والحافة هي Nginx. إذا أصبت في هذا الحد، يبقى تطبيقك بسيطًا
وداخليًا بينما يتعامل الـ proxy مع السطح العام المعادي؛ وإذا أخطأت، فإما أنك تكشف
التطبيق مباشرة (لا TLS، لا حماية) أو تدفع منطق الحافة إلى التطبيق حيث لا ينتمي.

الحكم الذي يعلّمه هذا الفصل هو **الـ proxy هو حد أمني وموثوقية، وإعداداته الافتراضية
ليست إعدادات الإنتاج.** قد يظل الـ reverse proxy الذي "يعمل" — أي تصل الطلبات عبره —
يفتقر إلى إعادة توجيه HTTPS، أو يوجّه عنوان IP العميل الخاطئ، أو يستخدم مهلات
عدوانية جدًا (أو أبدًا)، أو يسمح بأحجام رفع غير محدودة، ويُسرّب تفاصيل الخادم في
الرؤوس. جعله جاهزًا للإنتاج هو مجموعة محددة من القرارات: TLS حقيقي من Let's Encrypt
مع تجديد تلقائي، رؤوس proxy صحيحة ليرى التطبيق العميل الحقيقي، مهلات وحدود حجم جسم
معقولة، إعادة توجيه HTTP→HTTPS، رؤوس الأمان (HSTS وما شابه)، و gzip. يضع هذا الفصل
Nginx مُحَصَّنًا أمام حاوية Invoicely في Compose (الفصل 03)، على نطاق حقيقي، مع HTTPS
تلقائي — الباب الأمامي الذي يكشفه نشر الـ VPS (الفصل 06).

## لماذا هذا مهم

الحافة هي المكان الذي يُقرَّر فيه الأمان والموثوقية والعقد العام لتطبيقك:

- **TLS غير قابل للتفاوض، ولا ينبغي للتطبيق التعامل معه.** المستخدمون والمتصفحات
  و SEO وكل API حديث تتطلب HTTPS؛ HTTP العادي يُسرّب بيانات الاعتماد ويُصنَّف
  بأنه "غير آمن". إنهاء TLS في الـ proxy يعني أن مكانًا واحدًا يدير الشهادات
  والتجديد، وأن تطبيقك يتحدث HTTP بسيطًا داخليًا. افعل ذلك في التطبيق وستعيد كل
  خدمة تنفيذ معالجة الشهادات بشكل سيئ.
- **يحمي الـ proxy التطبيق من السطح العام المعادي.** المهلات توقف عميل slow-loris
  من حجز الـ workers؛ وحد حجم الجسم يوقف رفعًا بحجم 2 جيجابايت من استنفاد الذاكرة؛
  تحديد المعدل (وعمق المرحلة 9) يكبح إساءة الاستخدام. بدون هذه، عميل واحد سيئ
  السلوك يُضعف الخدمة بأكملها — وإعدادات التطبيق الافتراضية عادةً ما تكون خاطئة
  لنقطة نهاية عامة.
- **رؤوس Proxy الخاطئة تكسر الأمان والتسجيل بصمت.** خلف الـ proxy، يرى التطبيق
  عنوان IP الـ proxy ما لم توجّه العنوان الحقيقي (`X-Forwarded-For`) ويثق التطبيق
  به بشكل صحيح. أخطأت في هذا وتعمل حدود المعدل وسجلات التدقيق ومنطق الموقع
  الجغرافي جميعها على أساس العنوان الخاطئ، ويفشل اكتشاف `https` (`X-Forwarded-Proto`)
  — فيظن التطبيق أنه على HTTP ويبني عناوين إعادة توجيه معطوبة أو يرفض ملفات تعريف
  الارتباط الآمنة.
- **النطاق هو الهوية العامة، و DNS/TLS لهما حواف حادة.** سجل A يشير إلى الخادم،
  وشهادة تطابق اسم المضيف، و `www` مقابل apex، وتأخيرات الانتشار، و*التجديد
  التلقائي* (تنتهي صلاحية الشهادات كل 90 يومًا مع Let's Encrypt — التجديد المنسي
  هو انقطاع للخدمة على مستوى الموقع) هي جميعها نقاط فشل تُسقط الموقع بطرق لا
  يمكن للتطبيق إصلاحها.
- **تفصل الحافة البنية عن الكشف.** نطاق واحد ومنفذ HTTPS واحد يمكن أن يقدّما
  backend و frontend وأصولًا ثابتة على منافذ داخلية مختلفة — ويمكنك إعادة هيكلة
  الخدمات دون تغيير العقد العام. هذا التوسط هو ما يجعل النظام قابلًا للتطور.

أصبت — Nginx مُحَصَّن واحد يُنهي TLS حقيقيًا متجددًا تلقائيًا، ويوجّه الرؤوس
الصحيحة، ويفرض المهلات والحدود، ويعيد توجيه HTTP إلى HTTPS، ويُعيّن رؤوس الأمان —
ويكون تطبيقك آمنًا على الإنترنت مع معالجة السطح المعادي عند الحافة. أخطأت وكشفت
التطبيق مباشرة، وقدمت HTTP عادي، وكسرت منطق IP العميل، أو استيقظت على شهادة منتهية
الصلاحية وموقع معطل.

البُعد المتعلق بالذكاء الاصطناعي: إعدادات Nginx هي المنطقة الكلاسيكية لـ "يبدو
صحيحًا، لكنه ليس إنتاجيًا" للمساعدين. يُولّدون `proxy_pass` يوجّه الحركة ويُغفل
تقريبًا كل ما يجعله آمنًا — لا `proxy_set_header` لـ IP/proto العميل الحقيقي، ولا
مهلات، ولا `client_max_body_size`، ولا إعادة توجيه HTTPS، ولا رؤوس أمان، وغالبًا
إعداد TLS مُهمَل أو موقّع ذاتيًا بدلاً من Let's Encrypt حقيقي مع تجديد تلقائي.
يعمل في العرض التوضيحي (الطلب يمر) ويكون خاطئًا للإنتاج في نصف دزينة من الطرق
الهادئة.

## النموذج الذهني

الـ reverse proxy هو الباب العام الوحيد؛ تعيش فيه TLS والتوجيه والحماية، وليس في
التطبيق:

```
   REVERSE PROXY = the single public entry point (the ONLY thing on 80/443)
                                    the internet
                                        │  https:// invoicely.com  (443)
                                        ▼
                          ┌───────────────────────────┐
                          │            NGINX           │  ← terminates TLS, routes, protects
                          │  · TLS termination (443)   │
                          │  · HTTP→HTTPS redirect (80)│
                          │  · routing by path/host    │
                          │  · timeouts, body limits   │
                          │  · security headers, gzip  │
                          │  · correct proxy headers   │
                          └─────────────┬─────────────┘
             plain HTTP over the private network (Compose), by SERVICE NAME:
              /api  →  backend:8000        /  →  frontend:3000       (never public)
        → the app speaks simple HTTP internally; the world only ever touches Nginx.

   FORWARD vs REVERSE PROXY
     forward proxy = in front of CLIENTS (outbound; a VPN/corporate proxy)
     reverse proxy = in front of SERVERS (inbound; this) — clients think Nginx IS the app

   TLS / HTTPS (terminate once, at the edge)
     Let's Encrypt (certbot) issues a FREE cert for your domain, AUTO-RENEWED every ~90 days.
        cert proves you control the domain (ACME challenge) → browser trusts the padlock.
        FORGET renewal → cert expires → whole site down. automation is mandatory, not optional.

   DOMAIN / DNS (the address that points at the box)
     A record   invoicely.com     → <server IP>          (apex)
     A/CNAME    www.invoicely.com  → <server IP>/apex     (pick canonical, redirect the other)
        DNS propagation takes minutes–hours; the cert is issued for the NAME, not the IP.

   THE PROXY HEADERS THAT MUST BE RIGHT (or security/logging breaks silently)
     proxy_set_header Host              $host;               ← app sees the real hostname
     proxy_set_header X-Real-IP         $remote_addr;        ← the true client IP (logs, limits)
     proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto $scheme;             ← app knows it's HTTPS (cookies, redirects)
```

أربعة مبادئ يحملها الفصل:

**نقطة دخول عامة واحدة، كل شيء آخر داخلي.** Nginx هو الخدمة الوحيدة على 80/443؛
يعيش الـ backend و frontend والأصول الثابتة على منافذ خاصة لا يمكن الوصول إليها إلا
من خلاله. هذا هو درس Compose (الفصل 03) مطبَّقًا عند الحافة — لا يُكشف التطبيق
أبدًا بشكل مباشر.

**أنهِ TLS مرة واحدة، عند الـ proxy، وأتمتة التجديد.** يحمل الـ proxy الشهادة،
ويتحدث HTTPS مع العالم، ويوجّه HTTP عادي داخليًا. تجعل Let's Encrypt الشهادات
الحقيقية مجانية؛ الجزء غير القابل للتفاوض هو *التجديد التلقائي*، لأن شهادة 90 يومًا
منسية هي انقطاع مضمون.

**يجب أن يرى التطبيق العميل والبروتوكول الحقيقيين.** خلف الـ proxy، لا يعرف
التطبيق إلا ما يقوله له الـ proxy. وجّه `Host` و `X-Real-IP`/`X-Forwarded-For` و
`X-Forwarded-Proto` بشكل صحيح — واعدل التطبيق ليثق بها — أو ينكسر IP العميل
واكتشاف HTTPS وملفات تعريف الارتباط الآمنة وعناوين إعادة التوجيه بطرق خفية.

**الإعدادات الافتراضية ليست إنتاجية؛ الحافة هي حيث تُحَصِّن.** المهلات، و
`client_max_body_size`، وإعادة توجيه HTTP→HTTPS، ورؤوس الأمان (HSTS)، و gzip لا
تظهر بالسحر — كل منها سطر متعمد. الـ proxy هو حيث تتم إدارة السطح العام المعادي،
لذا يعيش هذا التحصين هنا، وليس في التطبيق.

## مثال إنتاجي

تُخدم **Invoicely** على `https://app.invoicely.com` عبر حاوية Nginx واحدة في حزمة
Compose (الفصل 03)، وهي الخدمة الوحيدة التي تنشر المنافذ 80 و 443. كل شيء آخر —
FastAPI backend، و Next.js frontend — داخلي، يمكن لـ Nginx الوصول إليه عبر الشبكة
الخاصة بواسطة اسم الخدمة. المتطلب الذي يحرك الإعداد: **نطاق واحد، HTTPS دائمًا،
التطبيق لا يُكشف مباشرةً أبدًا، وشهادة تُجدّد نفسها حتى لا ينقطع الموقع بسبب
شهادة منسية**.

الإعداد: لدى DNS سجل A لـ `app.invoicely.com` يشير إلى الـ VPS، و `invoicely.com`
/ `www` تُعاد توجيهها إليه (مضيف أساسي canonical واحد). يستمع Nginx على 80
(معيدًا توجيه كل شيء إلى HTTPS) وعلى 443 (TLS مُنهي بشهادة Let's Encrypt تم
الحصول عليها وتجديدها تلقائيًا بواسطة Certbot). تُوجّه طلبات `/api/...` إلى
`backend:8000`؛ وكل شيء آخر يُوجّه إلى Next.js `frontend:3000`. يُوجّه كل
`proxy_pass` الـ `Host` الحقيقي و IP العميل و `X-Forwarded-Proto`، ويُعدَّل تطبيق
FastAPI ليثق بهذا الـ proxy (بحيث يرى عناوين IP العميل الحقيقية ويعرف أنه على
HTTPS). يفرض Nginx حد حجم جسم 20 ميجابايت (فواتير بمرفقات، وليست رفعًا بحجم 2
جيجابايت)، ومهلات قراءة/اتصال معقولة، و gzip، ورؤوس أمان تتضمن HSTS. يعمل تجديد
Certbot على مؤقت ويُعيد تحميل Nginx — لا تنتهي صلاحية الشهادة دون مراقبة. هذا
هو الباب الأمامي الذي يضع خلفه فصل VPS (الفصل 06) الخادم.

## هيكل المجلدات

يضيف الـ proxy مجموعة مركزة من الملفات — إعداد Nginx، ومادة ACME/TLS، وتخزين
الشهادات — محفوظة في الـ repo حيث تكون config-as-code (الفصل 01):

```
invoicely/
├── nginx/
│   ├── nginx.conf              main config: worker/gzip/log defaults + include of the site
│   ├── conf.d/
│   │   └── invoicely.conf      THE site: server blocks (80 redirect, 443 TLS), proxy routes
│   └── snippets/
│       ├── proxy-headers.conf  the proxy_set_header block, included by every location (DRY)
│       └── security-headers.conf  HSTS + security headers, included once
├── docker-compose.yml          nginx is a service here; publishes 80/443 (Chapter 03)
├── certbot/
│   ├── conf/                   Let's Encrypt certs + renewal config (a VOLUME — persists!)
│   └── www/                    ACME http-01 challenge webroot (Nginx serves it on port 80)
└── ...
```

لماذا هذا التخطيط:

- **`nginx.conf` يُضمّن `conf.d/*.conf`، وليس ملفًا عملاقًا واحدًا.** تعيش
  الإعدادات الافتراضية العامة (عمليات الـ worker، gzip، تنسيق السجل) في الملف
  الرئيسي؛ كل موقع/نطاق هو ملفه الخاص في `conf.d/`. هذا هو أسلوب Nginx ويحافظ
  على إعداد متعدد المواقع أو متنامٍ قابلًا للقراءة والمراجعة.
- **تحافظ `snippets/` المشتركة على DRY لرؤوس الـ proxy والأمان.** كتلة
  `proxy_set_header` وكتلة رأس الأمان متطابقتان عبر المواقع؛ تجميعهما في snippets
  مُضمّنة يعني أن إصلاح الرأس يحدث مرة واحدة، وليس في خمسة أماكن — المصدر الشائع
  لإعداد غير متسق ومُحَصَّن جزئيًا.
- **`certbot/conf` هي حالة دائمة ويجب أن تكون volume مُسمًّى.** تعيش الشهادات
  الصادرة وإعداد التجديد هنا؛ إذا لم تكن هذه مُستمرة (درس الـ volume في الفصل 03)،
  فإن كل إعادة بناء للحاوية تفقد الشهادة وتعيد الطلب من Let's Encrypt — مباشرة
  إلى حدود معدّلهم. عاملها كـ volume قاعدة البيانات.
- **`certbot/www` هو الـ webroot للتحدي.** تثبت Let's Encrypt أنك تتحكم في النطاق
  بجلب token عبر HTTP؛ يخدم Nginx هذا المسار على المنفذ 80 (الشيء الوحيد الذي
  يفعله المنفذ 80 إلى جانب إعادة التوجيه). إبقاؤها صريحة يجعل آلية التجديد مرئية
  بدلاً من أن تكون سحرًا.

## التنفيذ

إعداد `invoicely.conf` إنتاجي مع كتلتي server — المنفذ 80 (إعادة التوجيه + ACME)
والمنفذ 443 (TLS + التوجيه) — ومع كل سطر تحصين مشروح. هذا يفترض أن Nginx يعمل في
حزمة Compose ويصل إلى الخدمات بالاسم.

```nginx
# nginx/conf.d/invoicely.conf

# ---- Port 80: redirect everything to HTTPS, except the ACME challenge ----
server {
    listen 80;
    server_name app.invoicely.com;

    # Let's Encrypt fetches its verification token over plain HTTP — must NOT be redirected.
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Everything else → HTTPS. (No app is ever served over plain HTTP.)
    location / {
        return 301 https://$host$request_uri;
    }
}

# ---- Port 443: terminate TLS, harden, and route to internal services ----
server {
    listen 443 ssl;
    http2 on;
    server_name app.invoicely.com;

    # --- TLS: the Let's Encrypt certificate (auto-renewed by Certbot) ---
    ssl_certificate     /etc/letsencrypt/live/app.invoicely.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.invoicely.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;               # no legacy SSL/TLS 1.0/1.1
    ssl_ciphers HIGH:!aNULL:!MD5;

    # --- Protection: don't accept unbounded bodies or hang forever ---
    client_max_body_size 20m;                    # invoices with attachments, not 2GB uploads
    proxy_connect_timeout 5s;
    proxy_read_timeout    30s;
    proxy_send_timeout    30s;

    # --- Security headers (HSTS tells browsers "always HTTPS for this domain") ---
    include snippets/security-headers.conf;

    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    # --- Route: /api → FastAPI backend (internal, by service name) ---
    location /api/ {
        proxy_pass http://backend:8000;
        include snippets/proxy-headers.conf;     # the headers the app depends on
    }

    # --- Route: everything else → Next.js frontend ---
    location / {
        proxy_pass http://frontend:3000;
        include snippets/proxy-headers.conf;
    }
}
```

الـ snippet-ان اللذان يجب تضمينهما في كل location مُوجَّه / مرة واحدة لكل server:

```nginx
# nginx/snippets/proxy-headers.conf — the app is BLIND to the real client without these
proxy_set_header Host              $host;                        # real hostname (redirects, routing)
proxy_set_header X-Real-IP         $remote_addr;                 # true client IP (logs, rate limits)
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;   # client IP chain
proxy_set_header X-Forwarded-Proto $scheme;                      # app knows it's HTTPS (cookies!)
```

```nginx
# nginx/snippets/security-headers.conf
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;  # HSTS
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
# (Content-Security-Policy is app-specific; full header hardening is Stage 9.)
```

الحصول على الشهادة وتجديدها تلقائيًا باستخدام Certbot (التجديد هو الجزء المهم):

```bash
# One-time issuance: prove domain control via the http-01 challenge (Nginx serves the token on :80).
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d app.invoicely.com --email ops@invoicely.com --agree-tos --no-eff-email

# Renewal is AUTOMATIC and mandatory: a timer runs `certbot renew` twice daily; it renews
# only when <30 days remain, then reloads Nginx to pick up the new cert.
#   certbot renew --deploy-hook "docker compose exec nginx nginx -s reload"
# Verify it works WITHOUT waiting 90 days:
docker compose run --rm certbot renew --dry-run
```

الأشياء الثلاثة التي غالبًا ما تفصل هذا عن إعداد لا يوجّه الحركة فحسب:

- **`X-Forwarded-Proto` (وأن يثق التطبيق به) هو ما يجعل التطبيق يعرف أنه على
  HTTPS.** بدونه، يظن FastAPI خلف الـ proxy أن كل طلب HTTP: يبني عناوين إعادة توجيه
  بـ `http://`، وقد يرفض تعيين ملفات تعريف الارتباط `Secure`، وتنكسر عمليات رد
  نداء OAuth. يجب إخبار التطبيق ليثق بالـ proxy (مثلاً `--proxy-headers` /
  `--forwarded-allow-ips` لـ Uvicorn، أو `ProxyHeadersMiddleware` لـ Starlette) —
  الرأس وحده لا يكفي إذا تجاهله التطبيق.
- **`client_max_body_size` والمهلات هي حماية، وإعداداتها الافتراضية خاطئة.** حد
  الجسم الافتراضي في Nginx هو 1 ميجابايت (صغير جدًا للرفع الحقيقي — ستحصل على
  أخطاء 413 غامضة) ومهلاته الافتراضية قد تُعلِّق الـ workers على عملاء بطيئين.
  عيّنها لاحتياجاتك الحقيقية صراحةً؛ لا تكتشفها في الإنتاج.
- **يجب أن يبقى موقع تحدي ACME على HTTP عادي.** الاستثناء الوحيد لـ "أعِد توجيه
  كل شيء إلى HTTPS" هو `/.well-known/acme-challenge/` — تجلب Let's Encrypt الـ
  token عبر HTTP على المنفذ 80. أعد توجيهه أيضًا (خطأ شائع في النسخ واللصق) ويفشل
  التجديد وتنتهي صلاحية الشهادة في النهاية.

## قرارات هندسية

**اجعل الـ proxy نقطة الدخول العامة الوحيدة.** Nginx فقط يربط 80/443؛ كل خدمة
تطبيق داخلية، يُصل إليها بالاسم عبر الشبكة الخاصة. *المبرر:* لا ينبغي أن يواجه
التطبيق الإنترنت مباشرة (الفصل 01/03) — الـ proxy هو السطح المُحَصَّن الوحيد،
ومركزية الحد العام هي ما تتيح لك إضافة TLS والحدود والرؤوس في مكان واحد وإعادة
هيكلة الخدمات دون تغيير العقد العام.

**أنهِ TLS في الـ proxy مع Let's Encrypt، وأتمتة التجديد.** شهادات مجانية عبر
ACME، مُنهيّة في Nginx، مع تجديد Certbot على مؤقت وإعادة تحميل Nginx. *المبرر:*
HTTPS إلزامي وينبغي أن تكون الشهادات مجانية وذاتية الصيانة؛ مدة 90 يومًا تجعل
الأتمتة غير اختيارية — *سيُنسى* التجديد اليدوي في النهاية ويُسقط الموقع. استمر
volume الشهادة بحيث لا تؤدي إعادة البناء إلى إعادة الطلب ضمن حدود المعدل.

**وجّه العميل والبروتوكول الحقيقيين، واجعل التطبيق يثق بالـ proxy.** عيّن
`Host` و `X-Real-IP`/`X-Forwarded-For` و `X-Forwarded-Proto`، واعدل التطبيق
ليحترمها. *المبرر:* خلف الـ proxy يكون التطبيق أعمى عن العميل الحقيقي؛ الرؤوس
الصحيحة (وثقة التطبيق) هي ما يحافظ على صحة التسجيل وتحديد المعدل واكتشاف HTTPS
وملفات تعريف الارتباط الآمنة وعناوين إعادة التوجيه. هذا إعداد ذو صلة بالأمان،
وليس رفاهية.

**عيّن المهلات وحد حجم الجسم بشكل متعمد.** `client_max_body_size` صريح مطابق
للرفع الحقيقي، ومهلات connect/read/send. *المبرر:* يحمي الـ proxy التطبيق من
السطح العام المعادي — الأجسام غير المحدودة تستنفد الذاكرة، والمهلات المفقودة
تسمح للعملاء البطيئين بحجز الـ workers — وإعدادات Nginx الافتراضية (جسم 1 ميجابايت،
مهلات سخية) خاطئة لنقطة نهاية عامة. قرّرها؛ لا ترثها.

**أعِد توجيه HTTP→HTTPS وعيّن رؤوس الأمان (HSTS).** المنفذ 80 يعيد توجيه كل
شيء (باستثناء مسار ACME) إلى 443؛ يرسل 443 HSTS ورؤوس الأمان القياسية. *المبرر:*
لا ينبغي أن تنتقل أي بايتة من التطبيق بنص عادي، و HSTS يجعل المتصفحات ترفض حتى
محاولة HTTP لنطاقك — مُغلقًا نافذة التخفيض. (تحصين الرؤوس/CSP الكامل في المرحلة
9؛ هذا هو الأساس.)

**اختر اسم مضيف أساسي canonical واحدًا وأعِد توجيه الباقي.** اختر apex أو
`www`، واجعل DNS يشير إلى الخادم، وأعِد توجيه 301 للآخر إلى الأساسي؛ أصدر الشهادة
للأسماء التي تخدمها. *المبرر:* تقديم نفس التطبيق على اسمي مضيف يقسم ملفات تعريف
الارتباط و SEO والتخزين المؤقت، ويُضاعف سطح TLS؛ مضيف أساسي واحد مع إعادات
التوجيه يحافظ على نظافة الهوية والجلسات والشهادات.

## المقايضات

**Nginx مقابل Caddy مقابل Traefik مقابل load balancer سحابي.** Nginx مختبَر
ميدانيًا، منتشر في كل مكان، وقابل للتحكم إلى أقصى حد، لكنك تُعدّ TLS/التجديد بنفسك.
يقدم Caddy HTTPS *تلقائيًا* بتكوين شبه معدوم (رائع للإعدادات البسيطة). يكتشف
Traefik الحاويات تلقائيًا (جميل مع Docker/Kubernetes الديناميكي). يُحمّل الـ load
balancer السحابي (ALB، Cloud LB) TLS والتوسع إلى المزود. *متى يفوز Nginx:* تريد
التحكم وقابلية النقل والمهارة الأكثر قابلية للتحويل — وهو الخيار الصحيح الافتراضي
لـ VPS واحد. *متى يفوز Caddy:* تريد أن يعمل HTTPS "فقط" ولا تحتاج إلى قابلية ضبط
Nginx. *متى يفوز الـ LB السحابي:* أنت بالفعل في تلك السحابة وتريد TLS/توسع مُدار.
يُدرَّس Nginx هنا لأن المفاهيم تنتقل إلى كل منها.

**إنهاء TLS في الـ proxy مقابل end-to-end (إعادة التشفير إلى الـ backend).** إنهاء
TLS في الـ proxy (التطبيق يتحدث HTTP عادي داخليًا) أبسط وهو المعيار لمضيف موثوق
واحد/شبكة خاصة. إعادة التشفير من الـ proxy إلى الـ backend تضيف defense-in-depth
للثقة الصفرية أو عندما لا تكون الشبكة الداخلية موثوقة، بتكلفة إدارة شهادات داخلية
أيضًا. *أنهِ في الـ proxy لإعداد Compose لمضيف واحد؛* أعد التشفير عندما تقفز
القفزة الداخلية عبر حد غير موثوق (مصدر قلق ينمو في عالم العقد المتعددة للمرحلة 11).

**تحديد المعدل/WAF على مستوى الـ proxy مقابل على مستوى التطبيق مقابل خدمة
CDN/حافة.** الحماية الأساسية (المهلات، حدود الجسم، `limit_req`) في Nginx رخيصة
وقريبة من المعدن؛ CDN/WAF (Cloudflare) يضيف امتصاص DDoS وقواعد حافة لكنه اعتماد
وتكلفة آخران؛ التحديد على مستوى التطبيق يعرف سياق العمل (لكل مستخدم، لكل خطة).
*افعل الحماية الرخيصة على مستوى الـ proxy دائمًا؛* أضف CDN عندما تواجه إساءة
حقيقية أو تحتاج إلى تخزين مؤقت عالمي؛ احتفظ بحدود قواعد العمل في التطبيق. العمق
في المرحلة 9/11.

**Nginx واحد يفعل كل شيء مقابل فصل الاهتمامات.** Nginx واحد يتعامل مع TLS
والتوجيه والملفات الثابتة والتخزين المؤقت بسيط ومناسب لتطبيق واحد؛ الفصل (CDN
للثابت/التخزين المؤقت، الـ proxy للتوجيه) يتوسع أفضل لكنه يضيف أجزاء متحركة.
*ابدأ بـ Nginx واحد؛* يقدّم بشكل مريح أمام SaaS على خادم واحد، وتفصل فقط عندما
يطلب قلق محدد (تقديم ثابت عالمي، تخزين مؤقت حافة).

## الأخطاء الشائعة

**كشف التطبيق مباشرة بدلاً من توجيهه عبر proxy.** نشر منفذ الـ backend وتوجيه
المستخدمين إليه — لا TLS، لا حدود، لا رؤوس، التطبيق عارٍ على الإنترنت. *الإصلاح:*
Nginx فقط يربط 80/443؛ التطبيق داخلي، يُصل إليه عبر الـ proxy.

**نسيان `proxy_set_header`، فيرى التطبيق الـ proxy لا العميل.** لا
`X-Real-IP`/`X-Forwarded-*`، فتسجل السجلات وحدود المعدل ومنطق الموقع الجغرافي
جميعها على أساس IP Nginx، وغياب `X-Forwarded-Proto` يجعل التطبيق يظن أنه على
HTTP. *الإصلاح:* snippet proxy-headers في كل location مُوجَّه، واعدل التطبيق ليثق
بالـ proxy.

**نسيان التجديد التلقائي للشهادة.** شهادة تم الحصول عليها مرة واحدة، يدويًا، ثم
نُسيت — حتى انتهت صلاحيتها بعد 90 يومًا وألقى الموقع بأكمله أخطاء شهادة. *الإصلاح:*
Certbot على مؤقت مع reload hook؛ تحقق بـ `renew --dry-run`.

**إعادة توجيه تحدي ACME إلى HTTPS.** إعادة توجيه شاملة لـ "أعِد توجيه كل المنفذ
80 إلى HTTPS" تعيد توجيه `/.well-known/acme-challenge/` أيضًا، فلا تستطيع Let's
Encrypt التحقق ويفشل التجديد بصمت. *الإصلاح:* قدّم مسار ACME عبر HTTP؛ أعد توجيه
كل شيء آخر.

**ترك حجم الجسم والمهلات الافتراضية لـ Nginx.** حد الجسم الافتراضي 1 ميجابايت
يسبب أخطاء 413 غامضة على الرفع الحقيقي؛ المهلات الافتراضية تسمح للعملاء البطيئين
بتعليق الـ workers. *الإصلاح:* عيّن `client_max_body_size` والمهلات لمتطلباتك
الحقيقية صراحةً.

**لا إعادة توجيه HTTP→HTTPS (تقديم كليهما).** يجيب التطبيق على HTTP عادي وكذلك
HTTPS، فبعض الحركة غير مشفرة وتظهر مشكلات mixed-content/downgrade. *الإصلاح:*
المنفذ 80 يعيد التوجيه إلى 443؛ أضف HSTS ليكف المتصفحون عن محاولة HTTP.

**عدم استمرار volume الشهادة.** دليل شهادات Certbot ليس volume مُسمًّى، فإعادة
بناء الحاوية تفقد الشهادة وتعيد الطلب من Let's Encrypt — لتصل سريعًا إلى حدود
معدّلهم وتجد نفسك بدون شهادة. *الإصلاح:* دليل الشهادات volume دائم مُسمًّى
(الفصل 03).

## أخطاء الذكاء الاصطناعي

إعدادات Nginx هي منطقة "يُوجّه الحركة، ليس إنتاجيًا" المميزة للمساعدين — يعمل
`proxy_pass`، وتقريبًا كل الحماية مفقودة. راجع الإعدادات المولّدة ضد قائمة التحصين
كاملة، وليس "هل يمر الطلب".

### Claude Code: `proxy_pass` عارٍ بدون رؤوس أو مهلات أو حدود

عند طلب "ضع Nginx أمام التطبيق"، ينتج Claude Code عادةً كتلة server واحدة بـ
`proxy_pass` وقليلاً آخر — لا `proxy_set_header`، ولا `client_max_body_size`، ولا
مهلات، ولا رؤوس أمان — لأن هذا الحد الأدنى الذي يوجّه طلبًا، وتوجيه الطلب هو ما
يتحقق منه.

**الاكتشاف:** `location` بـ `proxy_pass` وبدون أسطر `proxy_set_header`؛ لا
`client_max_body_size`؛ لا `proxy_*_timeout`؛ لا رؤوس أمان؛ التطبيق يرى IP Nginx
في سجلاته؛ أخطاء 413 عند الرفع.

**الإصلاح:** اشترط تحصين الـ proxy الكامل:

> يحتاج إعداد الـ proxy هذا إلى أساسيات الإنتاج: `proxy_set_header` لـ `Host` و
> `X-Real-IP` و `X-Forwarded-For` و `X-Forwarded-Proto` في كل location مُوجَّه؛
> `client_max_body_size` صريح ومهلات connect/read/send؛ ورؤوس أمان (HSTS وما شابه).
  تأكد من أن سجلات التطبيق تعرض عناوين IP العميل الحقيقية وتعرف أنه على HTTPS.

### GPT: TLS موقّع ذاتيًا أو بدون تجديد تلقائي

عند المطالبة بـ HTTPS، غالبًا ما تُوصل نماذج عائلة GPT TLS بشهادة موقّعة ذاتيًا
(تحذيرات المتصفح) أو إصدار Let's Encrypt يدوي بدون أتمتة تجديد — HTTPS "يعمل" في
الإعداد لكنه إما غير موثوق أو قنبلة موقوتة بمدى 90 يومًا.

**الاكتشاف:** `openssl req -x509 ... self-signed` مقدّم كإعداد TLS؛ `certbot
certonly` لمرة واحدة بدون timer/cron/`--deploy-hook`؛ لا volume شهادة دائم؛ لا
تحقق `renew --dry-run`؛ شهادات ستنتهي صلاحيتها دون مراقبة.

**الإصلاح:** اشترط شهادات حقيقية ذات تجديد تلقائي:

> استخدم Let's Encrypt لشهادة موثوقة حقيقية، لا موقّعة ذاتيًا، وأعدّ التجديد
> التلقائي (مؤقت يشغّل `certbot renew` مع hook يعيد تحميل Nginx). استمر دليل
> الشهادات كـ volume مُسمًّى بحيث لا تؤدي إعادة البناء إلى إعادة الطلب. تحقق من
> التجديد بـ `certbot renew --dry-run`.

### Cursor: كسر تحدي ACME أو إعادة توجيه HTTPS

عند تعديل إعداد Nginx بشكل inline، يميل Cursor إلى إضافة "أعِد توجيه كل HTTP إلى
HTTPS" نظيف يلتقط مسار تحدي ACME أيضًا، أو يوجّه الرؤوس بشكل غير متسق عبر
المواقع (مُحَصَّن على مسار واحد، عارٍ على آخر) — لأن التعديل محلي ولا يرى ثوابت
الإعداد بأكمله.

**الاكتشاف:** منفذ 80 بـ `return 301 https://...` بدون استثناء لـ
`/.well-known/acme-challenge/`؛ رؤوس proxy موجودة في بعض `location` ومفقودة في
أخرى؛ snippet أمان مُضمَّن في كتلة server واحدة وليس أخرى؛ التجديد يفشل بعد
تعديل الإعداد.

**الإصلاح:** اشترط ثوابت الإعداد بأكمله:

> أبق مسار تحدي ACME (`/.well-known/acme-challenge/`) مخدومًا عبر HTTP عادي؛ أعد
> توجيه كل شيء *آخر* فقط إلى HTTPS. طبّق نفس snippets proxy-headers و
> security-headers باستمرار على كل location مُوجَّه — اجمعها في includes بحيث لا
> تنزلق. أعد تشغيل `renew --dry-run` بعد أي تغيير في المنفذ 80.

## أفضل الممارسات

**نقطة دخول عامة واحدة مُحَصَّنة.** Nginx فقط على 80/443؛ جميع خدمات التطبيق
داخلية. أضف TLS والحدود والرؤوس مرة واحدة، عند الحافة — لا تكشف التطبيق مباشرةً
أبدًا.

**TLS حقيقي ذاتي التجديد.** Let's Encrypt عبر Certbot، مُنهي في الـ proxy،
مجدد على مؤقت مع reload hook، دليل شهادة مُستمر. تحقق بـ `renew --dry-run`. HTTPS
إلزامي؛ الانتهاء قابل للوقاية.

**رؤوس Proxy صحيحة، وتطبيق يثق بالـ proxy.** `Host` و `X-Real-IP` و
`X-Forwarded-For` و `X-Forwarded-Proto` في كل مسار، بالإضافة إلى تعديل التطبيق
ليحترم الرؤوس المُوجَّهة. تأكد من عناوين IP العميل الحقيقية في السجلات واكتشاف
HTTPS الصحيح.

**حماية متعمدة: المهلات، حدود الجسم، إعادة التوجيه، رؤوس الأمان.** عيّن
`client_max_body_size` والمهلات للاحتياجات الحقيقية؛ أعِد توجيه HTTP→HTTPS (باستثناء
ACME)؛ أرسل HSTS ورؤوس الأمان القياسية. لا ترث إعدادات Nginx الافتراضية لنقطة
نهاية عامة.

**حافظ على الإعداد DRY وفي version control.** الإعدادات الافتراضية العامة في
`nginx.conf`، ملف واحد لكل موقع في `conf.d/`، كتل رؤوس مشتركة في includes
`snippets/` — بحيث يكون التحصين متسقًا ويحدث الإصلاح مرة واحدة. الإعداد هو كود
(الفصل 01).

**اسم مضيف أساسي canonical واحد.** اختر apex أو `www`، وأعِد توجيه الآخر، وأصدر
الشهادة لما تخدمه. هوية واحدة لملفات تعريف الارتباط و SEO و TLS.

## الأنماط المضادة

**التطبيق العاري.** التطبيق منشور مباشرة على الإنترنت بدون proxy — لا TLS، لا
حدود، لا رؤوس. العلامة: المستخدمون يضربون منفذ التطبيق؛ `http://` بمنفذ خام في
العنوان URL؛ التطبيق يُنهي TLS الخاص به.

**الـ Backend الأعمى.** `proxy_pass` بدون رؤوس مُوجَّهة، فيرى التطبيق IP الـ proxy
ويظن أنه على HTTP. العلامة: كل طلب مسجل من IP داخلي واحد؛ ملفات تعريف الارتباط
`Secure` وعناوين إعادة التوجيه `http://` معطوبة خلف HTTPS.

**الشهادة المنتهية الصلاحية.** TLS معد مرة واحدة يدويًا بدون أتمتة تجديد،
سينتهي صلاحيته حتمًا. العلامة: لا مؤقت/hook لـ Certbot، لا volume شهادة دائم،
"الموقع سقط وهو خطأ شهادة" كل ~90 يومًا.

**القفل الموقّع ذاتيًا.** شهادة موقّعة ذاتيًا مستخدمة في الإنتاج، تطلق تحذيرات
المتصفح وتدرّب المستخدمين على النقر عبر أخطاء الأمان. العلامة: `openssl ... -x509`
في الإعداد؛ `NET::ERR_CERT_AUTHORITY_INVALID`.

**التجديد المحظور لـ ACME.** إعادة توجيه HTTP→HTTPS شاملة تعيد توجيه تحدي ACME
أيضًا، فيفشل التجديد بصمت. العلامة: أخطاء تجديد حول مسار التحدي؛ فشل `--dry-run`
بعد تعديل المنفذ 80.

**Proxy بحدود افتراضية.** إعدادات Nginx الافتراضية متروكة في مكانها — حد جسم 1
ميجابايت يسبب أخطاء 413، مهلات سخية تسمح للعملاء البطيئين بتعليق الـ workers.
العلامة: إخفاقات رفع غامضة عند ~1 ميجابايت؛ workers محجوزة بسبب اتصالات بطيئة.

## شجرة القرار

"أنا أضع proxy أمام التطبيق (أو أراجع إعداد Nginx) — ما الذي يجب أن يكون صحيحًا؟"

```
ENTRY POINT
  Is Nginx the ONLY thing on 80/443, with all app services internal?
     no → stop exposing the app directly. one public door; everything else behind it.

TLS
  Is there a REAL (Let's Encrypt, not self-signed) certificate?          no → issue one via ACME.
  Is renewal AUTOMATED (timer + reload hook) and the cert dir PERSISTED? no → automate + persist.
        verify: certbot renew --dry-run passes.
  Is the ACME challenge path served over HTTP (not redirected)?          no → carve it out.

REDIRECT & HEADERS
  Does port 80 redirect everything (except ACME) to HTTPS?               no → add the 301.
  Are HSTS + security headers set on 443?                                no → add the snippet.

PROXY HEADERS (per proxied location)
  Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto all forwarded?     no → add proxy-headers snippet.
  Is the APP configured to trust the proxy (forwarded-allow-ips)?        no → configure it.
        verify: app logs show real client IPs; app knows it's HTTPS.

PROTECTION
  client_max_body_size set to real upload needs (not the 1MB default)?   no → set it.
  connect/read/send timeouts set?                                        no → set them.

DOMAIN
  DNS A record points at the server; one canonical host, others 301'd; cert covers the names served?
     any no → fix DNS / redirects / cert SANs.

CONSISTENCY
  Same proxy-headers + security snippets on EVERY location/server (via includes)?
     no → factor into snippets so hardening can't drift.
  all yes → it's a secure front door, not just a router.
```

## قائمة المراجعة

### قائمة مراجعة التنفيذ

- [ ] Nginx فقط يربط 80/443؛ جميع خدمات التطبيق داخلية (يُصل إليها باسم الخدمة).
- [ ] شهادة **Let's Encrypt** حقيقية تُنهي TLS في الـ proxy (`TLSv1.2`/`1.3` فقط).
- [ ] **التجديد التلقائي** للشهادة مُعد (مؤقت + Nginx reload hook) ومُتحقق منه بـ
      `renew --dry-run`؛ دليل الشهادة volume دائم.
- [ ] المنفذ 80 **يعيد التوجيه إلى HTTPS** — باستثناء
      `/.well-known/acme-challenge/`، المخدوم عبر HTTP.
- [ ] كل location مُوجَّه يوجّه `Host` و `X-Real-IP` و `X-Forwarded-For` و
      `X-Forwarded-Proto`، والتطبيق مُعد ليثق بالـ proxy.
- [ ] `client_max_body_size` ومهلات connect/read/send **مُعيَّنة** للاحتياجات
      الحقيقية (وليست الافتراضية).
- [ ] **HSTS** ورؤوس الأمان مُعيَّنة على server HTTPS.

### قائمة مراجعة البنية

- [ ] إعداد Nginx هو config-as-code مُتحكم في إصداره؛ مواقع في `conf.d/`، كتل
      مشتركة في includes `snippets/` (DRY، لا انزلاق).
- [ ] اسم مضيف أساسي canonical واحد؛ أسماء مضيف أخرى معاد توجيهها بـ 301 إليه؛
      الشهادة تغطي ما يتم تقديمه.
- [ ] TLS مُنهي في الـ proxy (التطبيق يتحدث HTTP داخليًا)، خيار ملائم لـ topology
      المضيف الواحد.
- [ ] حماية الحافة الأساسية (المهلات، حد الجسم، و `limit_req` حيث يلزم) موجودة؛
      عمق WAF/تحديد المعدل الأعمق مؤجل إلى المرحلة 9.

### قائمة مراجعة الكود

- [ ] لا خدمة تطبيق مكشوفة مباشرة على الإنترنت؛ الـ proxy فقط عام.
- [ ] لا `proxy_pass` يفتقد الرؤوس المُوجَّهة (راقب الإعدادات المولّدة بالذكاء
      الاصطناعي)؛ لا شهادة موقّعة ذاتيًا في الإنتاج؛ لا أتمتة تجديد مفقودة.
- [ ] مسار تحدي ACME غير ملتقط بواسطة إعادة توجيه HTTPS.
- [ ] حجم الجسم والمهلات مُعيَّنة صراحةً؛ رؤوس HSTS/الأمان موجودة.
- [ ] snippets الـ proxy والأمان مطبقة باستمرار على كل location (عبر includes).

### قائمة مراجعة النشر

- [ ] سجلات DNS A/AAAA تشير إلى الخادم وقد انتشرت قبل إصدار الشهادة.
- [ ] الشهادة صادرة و `renew --dry-run` ينجح على الخادم الفعلي.
- [ ] volume الشهادة دائم ومُنسوخ احتياطيًا؛ إعادة البناء لا تعيد طلب الشهادات.
- [ ] HTTPS مؤكد end-to-end (القفل، اسم المضيف الصحيح، إعادة توجيه HTTP→HTTPS
      تعمل) قبل الإطلاق.

## تمارين

**1. قدّم التطبيق ووجّه العميل بشكل صحيح.** ضع Nginx أمام Invoicely's backend
بحيث يوجّه `/api` إليه، وأثبت — من سجلات الطلبات الخاصة بالتطبيق نفسه — أنه
بدون رؤوس الـ proxy يرى التطبيق IP Nginx ويظن أنه على HTTP، و*معها* (وإعداد ثقة
على جانب التطبيق) يرى IP العميل الحقيقي ويعرف أنه HTTPS. الناتج هما عينتا
السجلات والـ diff الذي أصلحها.

**2. أصدر شهادة حقيقية وجددها تلقائيًا.** على نطاق تتحكم فيه مُوجَّه إلى خادم
اختبار، احصل على شهادة Let's Encrypt عبر تحدي http-01، وأعدّ التجديد التلقائي
مع reload hook، وأثبت أن التجديد يعمل بـ `certbot renew --dry-run` — ثم اكسر
عمدًا مسار ACME بإعادة توجيه HTTPS شاملة ولاحظ فشل dry-run، مُظهرًا ضرورة
الاستثناء. الناتج هو التجديد العامل وإعادة التوجيه المكسورة/المُصلحة.

**3. تحصّن ضد السطح المعادي.** بدءًا من `proxy_pass` عارٍ، أضف
`client_max_body_size` والمهلات وإعادة توجيه HTTP→HTTPS و HSTS/رؤوس الأمان؛ ثم
أظهر عمل كل حماية — 413 على رفع متجاوز الحد، مهلة عميل بطيء، طلب HTTP معاد
توجيهه، و HSTS في رؤوس الاستجابة. الناتج هو diff الإعداد والتقاط قصير لكل سلوك.

## قراءات إضافية

- **Nginx documentation — "Reverse Proxy" و `ngx_http_proxy_module`** (nginx.org/en/docs) —
  المرجع الموثوق لـ `proxy_pass` و `proxy_set_header` والمهلات والتخزين المؤقت
  وراء إعداد هذا الفصل.
- **Let's Encrypt & Certbot documentation** (letsencrypt.org, certbot.eff.org) — كيف
  تعمل تحديات ACME وكيف تأتمت الإصدار والتجديد بشكل صحيح، بما في ذلك تدفق
  http-01 webroot المستخدم هنا.
- **Mozilla SSL Configuration Generator** (ssl-config.mozilla.org) — يولّد كتلة
  `ssl_protocols`/`ssl_ciphers` حديثة وآمنة لـ Nginx؛ المصدر العملي لإعدادات TLS
  هنا.
- **MDN — HTTP headers: `Strict-Transport-Security` و `X-Forwarded-*` و `Forwarded`**
  (developer.mozilla.org) — دلالات دقيقة لـ HSTS ورؤوس التوجيه التي يعتمد عليها
  التطبيق.
- **المرحلة 7، الفصل 05 — CI/CD مع GitHub Actions** — الخطوة التالية: أتمتة
  البناء والاختبار والنشر للتطبيق وهذا الـ proxy بحيث يكون الشحن خط أنابيب، لا
  جلسة SSH يدوية.
