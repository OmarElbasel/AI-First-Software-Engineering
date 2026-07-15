# Docker والحاويات (Containerization)

## المقدمة

عبارة "يعمل على جهازي" (Works on my machine) هي أقدم فشل في عالم البرمجيات، والحاويات (Containerization) هي الحل الدائم. تأخذ الحاوية (container) تطبيقك وتُغلِّفه مع بيئة التشغيل والمكتبات وطبقة userland الخاصة بنظام التشغيل التي يحتاجها بالضبط، في صورة واحدة (image) واحدة تعمل بنفس الطريقة على حاسوبك المحمول، وفي CI، وعلى خادم الإنتاج. لا مزيد من "الخادم يحتوي على Python 3.10 لكنني بنيت على 3.12"، ولا مزيد من اعتماد (dependency) موجود في التطوير وغير موجود في الإنتاج، ولا مزيد من نشر (deploy) يعمل يوم الثلاثاء وينكسر يوم الخميس لأن أحدًا ما قام بـ `apt upgrade` على الصندوق. يتناول هذا الفصل كيفية حاوية تطبيق حقيقي بشكل جيد: فهم ماهية الحاوية فعليًا (عملية Linux، وليس جهازًا افتراضيًا)، وكتابة Dockerfile يُنتج صورة صغيرة وآمنة وقابلة للتكرار، وتجنب الأخطاء القليلة التي تحوّل "نحن نستخدم Docker" إلى "نُشحن صورة منتفخة، تعمل بصلاحيات root، وتُكسر ذاكرة التخزين المؤقت (cache) بحجم 1.5 جيجابايت."

الفكرة الأهم على الإطلاق: **الحاوية هي عملية Linux قابلة للتكرار ومعزولة تُعرَّف بصورة، والصورة هي ن artifact (مُخرَج) للبناء يجب أن تُعامِلها ككود مُجمَّع — صغيرة، غير قابلة للتغيير، مُنسَّقة بإصدارات، وتُبنى بالطريقة نفسها في كل مرة.** الصورة ليست لقطة (snapshot) تُعدِّلها يدويًا؛ إنها المُخرَج الحتمي (deterministic) لـ `Dockerfile`، طبقة تلو طبقة. إذا استوعبت هذا النموذج الذهني، فإن الشيئين المهمين ينبثقان منهما تلقائيًا: *Dockerfile* هو الكود المصدري (يُراجَع، موجود في المستودع، صديق لذاكرة التخزين المؤقت) و*الصورة* هي الـ artifact (غير قابلة للتغيير، مُوسومة، تُروَّج عبر البيئات). إن أخطأت هذا الفهم، فستحصل على الأنماط المضادة (anti-patterns): صور عملاقة، أسرار (secrets) مدمجة في الطبقات، حاويات تعمل بصلاحيات root، وبناءات لا يمكن لأحد تكرارها.

الحُكم الذي يُعلِّمه هذا الفصل هو: **احوِل إلى حاويات بوعي، لا للزينة.** من السهل كتابة Dockerfile "يعمل" ويكون في الوقت نفسه ضخمًا وبطيء في البناء وغير آمن وغير قابل للتكرار. الفرق بين Dockerfile للهواة وDockerfile للإنتاج يكمن كليًا في القرارات: صورة أساسية (base image) نحيفة، بناء متعدد المراحل (multi-stage builds) لترك أدوات البناء خلفها، ترتيب الطبقات الذي يُعظِّم إعادة استخدام ذاكرة التخزين المؤقت، `USER` بصلاحيات غير root، `.dockerignore` مناسب، أسرار تُمرَّر في وقت التشغيل (runtime) لا تُدمَج في الصورة، وفحص صحي (health check) مناسب. هذا الفصل هو تلك القرارات مطبَّقة على خلفية FastAPI لـ Invoicely وواجهة Next.js الأمامية — ثم يأتي الفصل 03 (Compose) ليربط الصور الناتجة في بيئة كاملة متعددة الخدمات.

## لماذا هذا مهم

الحاويات هي معيار التعبئة الذي يعمل عليه الإنتاج، وإتقانها بشكل سيئ مُكلِف بطرق تبقى مخفية حتى لا تعود كذلك:

- **قابلية التكرار (Reproducibility) هي كل شيء — وهي هشة.** الوعد هو "متطابق في كل مكان." صورة أساسية غير مُثبَّتة (`python:latest`)، أو اعتماد (dependency) غير مُثبَّت، أو `apt-get install` بدون إصدار مُقفَل، تكسر هذا الوعد بهدوء — فالصورة المبنية اليوم تختلف عن تلك المبنية الشهر الماضي، والعلة غير قابلة للتكرار. الحاوية لا تكون قابلة للتكرار إلا بقدر ما يكون Dockerfile منضبطًا.
- **حجم الصورة هو سرعة النشر، والتكلفة، وسطح الهجوم.** صورة بحجم 1.5 جيجابايت تُدفَع ببطء، وتُسحَب ببطء عند كل نشر وتوسعة، وتكلِّف تخزينًا في السجل (registry)، وتُشحن مع نظام تشغيل كامل من الحزم (كل واحدة منها CVE محتملة) لا تستخدمها. صورة مبنية جيدًا لنفس التطبيق يمكن أن تكون 150 ميجابايت. الحجم ليس تباهيًا؛ إنه دقائق لكل نشر وشيء أكبر لتأمينه.
- **التخزين المؤقت للبناء هو وقت المطور.** يبني Docker في طبقات ويُخزِّنها مؤقتًا؛ إن أخطأت ترتيب الطبقات (نسخ كل كودك قبل تثبيت الاعتماديات) فإن كل تغيير بسطر واحد يُعيد تثبيت كل الاعتماديات — مما يحوِّل إعادة بناء مدتها 5 ثوانٍ إلى 5 دقائق، عشرات المرات في اليوم، في CI ومحليًا.
- **الحاويات التي تعمل بصلاحيات root هي خطر حقيقي.** الحاوية ليست حدًا أمنيًا بالطريقة التي يكون بها الـ VM؛ فالعملية التي تعمل كـ root داخل الحاوية تكون قريبة من root على المضيف بطرق تهم عند وجود CVE لهروب من الحاوية أو عند تركيب وحدة تخزين (mounted volume). العمل كـ root هو الافتراضي، وهو الافتراضي الخاطئ.
- **الأسرار المدمجة في الصورة تتسرَّب بشكل دائم.** أي سر يُنسَخ (`COPY`) أو يُمرَّر كـ `ARG` داخل طبقة يبقى في سجل الصورة (image history) إلى الأبد، قابل للاستخراج من قِبل أي شخص يسحب الصورة، حتى لو حذفته طبقة لاحقة. تُدفَع الصور إلى السجلات (registries)؛ والسر المدمج هو سر منشور.

إن أصبت — صورة نحيفة، متعددة المراحل، بصلاحيات غير root، صديقة لذاكرة التخزين المؤقت، مبنية من صورة أساسية مُثبَّتة، مع أسرار تُحقَن في وقت التشغيل — فستنشر بسرعة، وبتكلفة منخفضة، وبأمان، وبشكل متطابق عبر كل البيئات. إن أخطأت، فأنت تُشحن artifact بطيئة ومنتفخة وغير آنة تختلف في كل مرة تبنيها.

البُعد المتعلق بالذكاء الاصطناعي: هذه إحدى المجالات التي يكون فيها المساعدون *واثقين بمعدل متوسط*. يُنتجون Dockerfiles تعمل في العرض التوضيحي وتخرق معظم قواعد الإنتاج دفعة واحدة — `FROM python` (غير مُثبَّت، ممتلئ)، لا multi-stage، `COPY . .` قبل `pip install` (يكسر ذاكرة التخزين المؤقت)، لا `USER` (يعمل كـ root)، لا `.dockerignore`، وأحيانًا سر مدمج في الصورة. كل واحدة منها تنجح في `docker build` وفي اختبار دخاني. الحاويات هي بالتحديد المكان الذي يتباعد فيه "يعمل" و"على مستوى الإنتاج" أكثر ما يمكن، وحيث تُؤتي مراجعة Dockerfile الذي يُنتِجه الذكاء الاصطناعي وفق معايير حقيقية ثمارها.

## النموذج الذهني

الحاوية هي عملية Linux معزولة؛ والصورة هي مخططها القابل للتكرار والمُطبَّق في طبقات:

```
   CONTAINER ≠ VM
     VM         = full guest OS + kernel on a hypervisor    (GBs, boots in seconds)
     CONTAINER  = an isolated PROCESS sharing the host kernel (MBs, starts instantly)
        isolation via Linux namespaces (its own PIDs, network, mounts) + cgroups (limits)
        → it's Chapter 01's process model, walled off. Not a smaller VM.

   IMAGE = the blueprint (build artifact) │ CONTAINER = a running instance of it
     image: immutable, tagged, layered, in a registry   (like a class / compiled binary)
     container: a live process from an image             (like an object / a run)
        docker build → image    docker run image → container    docker push → registry

   IMAGES ARE LAYERS (this is why order matters)
     each Dockerfile instruction = a cached layer, stacked:
        FROM python:3.12-slim         ← base (pin it)
        COPY requirements.txt .       ← changes rarely  ┐ put SLOW, STABLE steps
        RUN pip install -r ...        ← slow, cacheable ┘ EARLY so cache survives
        COPY . .                      ← changes often   ┐ put FAST, VOLATILE steps
        CMD [...]                     ← the entrypoint  ┘ LATE
     change a layer → it and everything AFTER it rebuilds. order least→most volatile.

   MULTI-STAGE (ship the artifact, not the toolchain)
     STAGE 1 "builder": full toolchain, compile/install deps          (heavy, discarded)
     STAGE 2 "runtime": slim base + COPY --from=builder just the output (small, shipped)
        → build tools never reach the final image. 1.5 GB → 150 MB.

   THE PRODUCTION CHECKLIST (what separates a real Dockerfile)
     pinned slim base · multi-stage · deps before code (cache) · .dockerignore ·
     USER non-root · secrets at RUNTIME not baked · HEALTHCHECK · one process per container
```

أربعة مبادئ يحملها الفصل:

**الحاوية عملية، وليست VM.** تتشارك نواة المضيف وتُعزَل عبر namespaces وcgroups — ولهذا هي بالميجابايتات وتبدأ لحظيًا، ولهذا يختلف نموذج الأمان عن الـ VM (ومن هنا: لا تشغِّلها كـ root). كل شيء من الفصل 01 (العمليات، المنافذ، المستخدمون) لا يزال ينطبق داخلها.

**الصورة هي ن artifact للبناء؛ وDockerfile هو مصدرها.** عامل Dockerfile ككود — يُراجَع، موجود في المستودع، حتمي — والصورة كالثنائي المُجمَّع (compiled binary) — غير قابلة للتغيير، مُوسومة، مُروَّجة عبر البيئات، لا تُعدَّل يدويًا. قابلية التكرار تأتي من تثبيت كل ما يعتمد عليه البناء.

**ترتيب الطبقات هو استراتيجية التخزين المؤقت.** التعليمات تصبح طبقات مُخزَّنة مؤقتًا؛ أي تغيير يُبطل تلك الطبقة وكل ما بعدها. ضع الخطوات البطيئة والمستقرة (تثبيت الاعتماديات) قبل السريعة والمتغيرة (نسخ المصدر). هذا القرار وحده هو الفرق بين إعادة بناء مدتها 5 ثوانٍ وأخرى مدتها 5 دقائق.

**اشحن الـ artifact، لا سلسلة الأدوات (toolchain).** عمليات البناء متعددة المراحل (multi-stage) تُجمِّع/تُثبِّت في مرحلة builder ثقيلة، وتنُسخ النتيجة فقط إلى مرحلة runtime نحيفة — تاركة المُجمِّعات (compilers) والترويسات (headers) وذاكرة التخزين المؤقت للحزم خلفها. الصور الصغيرة أسرع، وأرخص، وسطح هجومها أصغر.

## مثال إنتاجي

**Invoicely** تُشحن صورتين: خلفية FastAPI وواجهة Next.js الأمامية، كلتاهما تُبنَيان بواسطة CI (الفصل 05)، وتُدفَعان إلى سجل (registry)، وتُشغَّلان بواسطة Compose (الفصل 03) في التطوير وعلى الـ VPS (الفصل 06). المتطلب الذي يحرك كل قرار هنا: **الصورة المبنية في CI يجب أن تكون البايتات نفسها التي تعمل في الإنتاج** — نفس Python، ونفس الاعتماديات، ونفس مكتبات نظام التشغيل — ويجب أن تكون صغيرة بما يكفي لدفعها وسحبها في ثوانٍ، وآمنة بما يكفي لكشفها.

إن Dockerfile للخلفية هو multi-stage: مرحلة `builder` على `python:3.12-slim` تُثبِّت الاعتماديات في virtualenv بإصدارات مُثبَّتة؛ مرحلة `runtime` على نفس الـ slim base تنُسخ الـ virtualenv وكود التطبيق فقط، وتُضيف `appuser` بصلاحيات غير root، وتضبط `HEALTHCHECK` يستهدف `/health`، وتُشغِّل `uvicorn`. النتيجة ~180 ميجابايت بدلًا من ~1 جيجابايت، تعمل بـ UID 1000 وليس root، وتُعاد بناؤها في ثوانٍ عند تغير كود التطبيق فقط (الاعتماديات تبقى مُخزَّنة مؤقتًا)، ولا تحمل سلسلة أدوات (toolchain) إلى الإنتاج. الأسرار — رابط قاعدة البيانات، ومفتاح JWT، ومفتاح Stripe — **ليست** في الصورة؛ بل تُحقَن في وقت التشغيل عبر متغيرات البيئة (الفصل 03). ينطبق نفس الانضباط على صورة Next.js، التي تستخدم بالإضافة إلى ذلك مُخرَج `standalone` الخاص بـ Next لتشحن ملفات runtime المُتتبَّعة (traced) فقط. هاتان الصورتان هما الـ artifacts القابلة للنشر التي تنسِّقها بقية المرحلة.

## بنية المجلدات

الحاويات تلمس بضعة ملفات في جذر المستودع؛ كل واحد يستحق مكانه، و `.dockerignore` بنفس أهمية Dockerfile:

```
invoicely/
├── backend/
│   ├── Dockerfile              the backend image's SOURCE — reviewed, pinned, multi-stage
│   ├── .dockerignore           what NOT to send to the build (as important as Dockerfile)
│   ├── requirements.txt        PINNED deps — copied & installed BEFORE code (cache layer)
│   └── app/                    application code — copied AFTER deps (volatile layer)
│       └── main.py
├── frontend/
│   ├── Dockerfile              the frontend image (multi-stage: deps → build → standalone)
│   ├── .dockerignore
│   ├── package.json
│   └── ...
├── docker-compose.yml          wires the images into a running system (Chapter 03)
└── .env.example                template for the RUNTIME secrets (never baked into images)
```

لماذا هذه:

- **`Dockerfile` يعيش بجانب ما يبنيه وهو كود مصدري.** واحد لكل خدمة، في المستودع، يُراجَع كأي كود — لأن قابلية تكرار الصورة وأمانها يُقرَّران كليًا هنا.
- **`.dockerignore` يتحكم في سياق البناء (build context)، وغيابه علة شائعة.** بدونه، يُرسل `docker build` المجلد بالكامل — `.git`، `node_modules`، `.env` المحلي، `__pycache__`، الـ `.venv` — إلى الـ daemon: بناءات بطيئة، سياق منتفخ، والخطر الحقيقي أن `.env` محلي يُنسَخ عبر `COPY . .` إلى الصورة. هو أول ملف يجب إضافته.
- **`requirements.txt`/`package.json` يُنسَخان منفصلين وأولًا.** ملف اعتماديات يُنسَخ ويُثبَّت *قبل* المصدر، لتبقى طبقة التثبيت (البطيئة) مُخزَّنة مؤقتًا عبر تغييرات الكود. هذا الفصل هو استراتيجية التخزين المؤقت بأكملها.
- **`.env.example` قالب، وليس سرًا.** يوثِّق متغيرات وقت التشغيل التي تتوقعها الصورة، وتُحقَن عند `docker run`/وقت Compose — أما الـ `.env` الحقيقي فيُستبعَد من git ولا يدخل الصورة أبدًا.

## التطبيق

Dockerfile خلفي للإنتاج يُجسِّد كل المبادئ أعلاه. اقرأ التعليقات على أنها *التفكير*، وليس زينة:

```dockerfile
# backend/Dockerfile

# ---- Stage 1: builder — has the toolchain, produces the venv, then is DISCARDED ----
FROM python:3.12-slim AS builder          # PINNED + slim (not python:latest, not full python)

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Copy ONLY the dependency manifest first, so the slow install layer caches
# across source-code changes (the leftmost-volatility rule from the mental model).
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r requirements.txt

# ---- Stage 2: runtime — slim base, no toolchain, non-root, just the app ----
FROM python:3.12-slim AS runtime

# Create a dedicated non-root user (Chapter 01's least-privilege, inside the container).
RUN groupadd --system app && useradd --system --gid app --uid 1000 appuser

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1                    # logs stream to stdout immediately (Chapter 07)

WORKDIR /app

# Bring ONLY the built virtualenv from the builder — the compilers/caches stay behind.
COPY --from=builder /opt/venv /opt/venv
# Then the application code (the most volatile layer, so it's last).
COPY --chown=appuser:app ./app ./app

USER appuser                             # drop from root — everything below runs as appuser

EXPOSE 8000                              # documents the port (does not publish it)

# The orchestrator/Nginx uses this to know the container is actually ready, not just up.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

# exec form (JSON array) so the process is PID 1 and receives SIGTERM for graceful shutdown.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

ملف `.dockerignore` المُطابِق — صغير، عالي الأثر، وأكثر ملف يُنسى:

```gitignore
# backend/.dockerignore
.git
.venv
__pycache__/
*.pyc
.env                 # NEVER let a local secrets file into the build context
.pytest_cache/
tests/               # tests don't belong in the runtime image
*.md
```

البناء، والتشغيل، وحقن الأسرار في وقت التشغيل (أبدًا في وقت البناء):

```bash
# Build a tagged, immutable artifact (tag = the git SHA in CI — Chapter 05).
docker build -t invoicely-backend:1.4.2 ./backend

# Run it, injecting secrets at RUNTIME via env — they are not in the image.
docker run --rm -p 8000:8000 \
  --env-file .env \                      # DATABASE_URL, JWT_SECRET, STRIPE_KEY, ...
  --name invoicely-backend \
  invoicely-backend:1.4.2

docker image ls invoicely-backend        # confirm the size is ~180MB, not ~1GB
docker history invoicely-backend:1.4.2   # inspect layers; verify NO secret is in any layer
```

تفصيلان من السهل تفويتهما ومهمان جدًا:

- **`CMD` تستخدم صيغة exec (`["uvicorn", ...]`)، وليس صيغة الـ shell (`uvicorn ...`).** صيغة الـ shell تُشغِّل عمليتك كفرع لـ `/bin/sh`، فيكون `sh` هو PID 1 وتطبيقك *لا يستقبل `SIGTERM`* عند `docker stop` — بل يحصل على `SIGKILL` بعد مهلة، متخطيًا الإيقاف السلس (draining connections، إغلاق pool قاعدة البيانات). صيغة exec تجعل تطبيقك PID 1 ويتوقف بسلاسة.
- **`0.0.0.0` داخل الحاوية صحيح** — تعني "كل الواجهات *داخل* نطاق الشبكة الخاص بالحاوية"، يمكن لـ Compose/Nginx الوصول إليها على شبكة الحاوية. هذا ليس نفس ربط `0.0.0.0` على المضيف (الفصل 01)؛ شبكة الحاوية معزولة، ولا تُكشف إلا المنافذ التي تنشرها/تعمل لها proxy.

## قرارات هندسية

**ثبِّت صورة أساسية نحيفة، أبدًا `latest` أو ممتلئة.** استخدم `python:3.12-slim` (أو `-alpine` بعين مفتوحة، أو distroless runtime)، مُثبَّتة على إصدار محدد. *السبب:* `latest` يجعل البناءات غير قابلة للتكرار (تتغير تحتك) والصورة الكاملة تشحن مئات الميجابايتات وCVEs لا تستخدمها. التثبيت + النحافة قابلية تكرار وسطح هجوم أصغر في قرار واحد.

**استخدم بناءات multi-stage لتترك سلسلة الأدوات خلفها.** اجمع/ثبِّت في مرحلة builder؛ انسخ النتيجة فقط إلى مرحلة runtime نحيفة. *السبب:* أدوات البناء (gcc، الترويسات، ذاكرة التخزين المؤقت للحزم، اعتمادات التطوير) مطلوبة للـ *بناء* وهي مجرد سطح هجوم وانتفاخ في *وقت التشغيل*. multi-stage هو الرافعة الأكبر على حجم الصورة.

**رتِّب الطبقات من الأقل تغيرًا إلى الأكثر تغيرًا.** انسخ وثبِّت الاعتماديات قبل نسخ المصدر. *السبب:* أي تغيير في طبقة يُعيد بناءها وكل ما بعدها؛ وضع تثبيت الاعتماديات البطيء والمستقر أولًا يعني أن تغيير سطر واحد في الكود يُعيد استخدام الاعتماديات المُخزَّنة مؤقتًا بدلًا من إعادة تثبيت كل شيء. هذا هو الفرق بين التكرار السريع والمؤلم.

**شغِّل بـ `USER` بصلاحيات غير root.** أنشئ مستخدمًا مخصصًا وانتقل إليه قبل `CMD`. *السبب:* الحاويات ليست حدًا أمنيًا صلبًا؛ root داخل الحاوية امتياز غير ضروري يصبح مهمًا عند وجود CVE لهروب من الحاوية أو عند تركيب وحدات تخزين. يكلِّفك سطرين وهو متطلب إنتاجي وليس رفاهية.

**احقن الأسرار في وقت التشغيل، أبدًا تُدمجها في الطبقات.** تأتي الأسرار من متغيرات البيئة / الأسرار المُركَّبة في وقت `docker run`/Compose. *السبب:* أي شيء يُنسَخ (`COPY`) أو يُمرَّر كـ `ARG` داخل طبقة يبقى في سجل الصورة إلى الأبد، قابل للاستخراج من أي سحب — والسر المدمج هو سر منشور، و`rm` لاحق لا يزيله من السجل.

**أضف `HEALTHCHECK` واستخدم صيغة exec في `CMD`.** فحص الصحة يُتيح للمُنسِّق (orchestrator) معرفة *الجاهزية* مقابل مجرد *البدء*؛ وصيغة exec تجعل تطبيقك PID 1 فيستقبل `SIGTERM`. *السبب:* بدون فحص الصحة، تصل حركة المرور إلى تطبيق لم يصبح جاهزًا بعد؛ وبدون صيغة exec، تفقد الإيقاف السلس وتُسقِط الطلبات قيد التنفيذ عند كل نشر.

## المفاضلات (Trade-offs)

**حجم الصورة مقابل ألفة القاعدة: `slim` مقابل `alpine` مقابل `distroless`.** `-slim` (Debian، glibc) هو الافتراضي الآمن — صغير ومتوافق. `-alpine` (musl libc) أصغر، لكنه قد يكسر حزم Python التي لها امتدادات C ويُنتج أخطاء محيِّرة (DNS، المناطق الزمنية، wheels غير الموجودة لـ musl). `distroless` هو الأصغر والأكثر أمانًا (لا shell، لا مدير حزم) لكنه صعب التصحيح (لا shell لتنفيذ exec داخله). *افتراضيًا اختر `-slim`*؛ انتقل إلى distroless عندما تريد أقل سطح هجوم وتكون قد رتَّبت مسألة التصحيح؛ استخدم `-alpine` فقط عندما تكون قد تحققت من أن اعتماداتك تعمل على musl.

**سرعة البناء مقابل حجم الصورة مقابل قابلية التكرار.** البناء متعدد المراحل العدواني وسحق الطبقات (layer squashing) يُقلِّل الحجم؛ التخزين المؤقت يُعظِّم السرعة؛ تثبيت كل شيء يُعظِّم قابلية التكرار — وأحيانًا تتعارض هذه الأهداف (مثلًا دمج `RUN`s في طبقات أقل قد يُضعِف دقة التخزين المؤقت). *ترتيب الأولويات للإنتاج:* قابلية التكرار أولًا (ثبِّت، لا تستخدم `latest`)، ثم الحجم (multi-stage، slim)، ثم السرعة (ترتيب الطبقات، تركيبات التخزين المؤقت). لا تُضحِّ بقابلية التكرار أبدًا من أجل بناء أسرع.

**الحاويات مقابل النشر الأصلي (systemd).** تمنحك الحاويات تطابق البيئة، والعزل، و artifact مبني في CI؛ النشر الأصلي (الفصل 01) أبسط بطبقة أقل. *هذه هي نفس مفاضلة الفصل 01* — معظم SaaS متعدد الخدمات يكسب بالحاويات لمجرد التطابق؛ قد لا تحتاجها خدمة بسيطة واحدة. لا تحوِّل سكريبت من ملف واحد إلى حاوية لتبدو عصريًا.

**عملية واحدة لكل حاوية مقابل حشر عدة عمليات فيها.** نموذج Docker هو concern واحد لكل حاوية (تطبيق، قاعدة بيانات، cache لكل واحد منها)، تُنسَّق معًا (الفصل 03). حشر Nginx + تطبيق + cron في حاوية واحدة مع مدير عمليات ممكن لكنه يُصارع النموذج — فالتوسع المستقل، والسجلات المستقلة، وإعادة التشغيل النظيفة كلها تنكسر. *فضِّل عملية واحدة لكل حاوية*؛ ودع Compose/التنسيق يقوم بالتركيب.

## الأخطاء الشائعة

**استخدام `FROM python:latest` (أو `node:latest`).** غير مُثبَّت وممتلئ: البناءات غير قابلة للتكرار (الوسم يتحرك) والصورة فيها مئات الميجابايتات من الحزم غير المستخدمة وCVEs. *الإصلاح:* ثبِّت وسمًا نحيفًا محددًا (`python:3.12-slim`) وأعد البناء بوعي عندما تختار الترقية.

**`COPY . .` قبل تثبيت الاعتماديات.** كل تغيير في المصدر يكسر التخزين المؤقت ويُعيد تثبيت كل الاعتماديات، مما يجعل كل إعادة بناء بطيئة. *الإصلاح:* انسخ ملف الاعتماديات (`requirements.txt`/`package.json`) وثبِّته أولًا، ثم انسخ المصدر.

**لا يوجد `.dockerignore`.** المجلد بالكامل — `.git`، `node_modules`، `.venv`، `.env` المحلي — يُرسَل كسياق بناء: بناءات بطيئة، والأسوأ، احتمال حقيقي أن `COPY . .` يدمج `.env` محليًا في الصورة. *الإصلاح:* أضف `.dockerignore` يستبعد VCS والاعتماديات وذاكرة التخزين المؤقت والأسرار.

**تشغيل كـ root.** لا يوجد سطر `USER`، فالحاوية تعمل كـ root — امتياز غير ضروري ونصف قطر انفجار أكبر عند أي هروب. *الإصلاح:* أنشئ مستخدمًا بصلاحيات غير root واستخدم `USER` إليه قبل `CMD`.

**دمج الأسرار في الصورة.** `COPY .env` أو `ARG API_KEY=...` يضع الأسرار في سجل الطبقات إلى الأبد، قابلة للاستخراج من أي سحب. *الإصلاح:* احقن الأسرار في وقت التشغيل عبر متغيرات البيئة / الأسرار المُركَّبة؛ أبقِ `.env` خارج السياق.

**لا يوجد بناء multi-stage.** شحن سلسلة الأدوات الكاملة (المُجمِّعات، ترويسات التطوير، ذاكرة التخزين المؤقت للحزم) في صورة الـ runtime — ضخم وسطح هجوم أكبر. *الإصلاح:* ابنِ في مرحلة builder، وانسخ الناتج فقط في مرحلة runtime نحيفة.

**صيغة shell في `CMD` ولا فحص صحة.** `CMD uvicorn ...` تجعل `sh` هو PID 1 (لا `SIGTERM` سلس)؛ ولا `HEALTHCHECK` يعني أن المُنسِّق لا يستطيع التمييز بين الجاهز والمُبتدئ. *الإصلاح:* صيغة exec في `CMD` و`HEALTHCHECK` يستهدف endpoint جاهزية حقيقي.

## أخطاء الذكاء الاصطناعي

Dockerfiles هي مكان يُنتج فيه المساعدون شيئًا يُبنى وينجح في اختبار دخاني مع خرق عدة قواعد إنتاج دفعة واحدة. راجِع كل Dockerfile مُولَّد وفق قائمة التحقق — "تم بناؤه" لا يثبت شيئًا ذا قيمة هنا تقريبًا.

### Claude Code: Dockerfile "يعمل لكن ليس إنتاجيًا"

عند طلب "أضف Dockerfile"، يُنتج Claude Code عادةً صورة بمرحلة واحدة على قاعدة غير مُثبَّتة أو ممتلئة، تعمل كـ root، مع `COPY . .` قبل `pip install` ولا `.dockerignore` — تُبنى وتعمل، فتبدو منتهية، لكنها كبيرة، وعدوة لذاكرة التخزين المؤقت، وتعمل كـ root.

**الكشف:** `FROM python`/`FROM node` (بدون وسم نحيف مُثبَّت)؛ مرحلة واحدة؛ `COPY . .` قبل تثبيت الاعتماديات؛ لا `USER`؛ لا ذكر لـ `.dockerignore`؛ لا `HEALTHCHECK`.

**الإصلاح:** اطلب شكل الإنتاج صراحةً:

> اجعل هذا Dockerfile للإنتاج: قاعدة نحيفة مُثبَّتة، multi-stage (builder → slim runtime)، انسخ وثبِّت الاعتماديات *قبل* نسخ المصدر (لتخزين الطبقات مؤقتًا)، `USER` بصلاحيات غير root، `.dockerignore` يستبعد `.git`/الاعتماديات/ذاكرة التخزين المؤقت/`.env`، و`HEALTHCHECK`. اعرض حجم الصورة.

### GPT: ترتيب طبقات يكسر التخزين المؤقت و`RUN` ضخم مُدمج

نماذج عائلة GPT غالبًا ما ترتِّب الطبقات بطريقة تجعل أي تغيير في الكود يُعيد تثبيت الاعتماديات (المصدر يُنسَخ قبل ملف الاعتماديات)، أو تضم كل شيء في `RUN` عملاق واحد يُنفِّخ طبقة واحدة ويُدمِّر دقة التخزين المؤقت — الصورة تُبنى بشكل صحيح لكن إعادة البناء بطيئة في كل مرة.

**الكشف:** `COPY . .` (أو التطبيق بالكامل) يظهر قبل تثبيت الاعتماديات؛ `RUN` واحد يقوم بـ apt-install + pip-install + تجهيز الكود معًا؛ لا فصل بين الطبقات المستقرة والمتغيرة؛ إعادات بناء تُعيد دائمًا تثبيت الاعتماديات.

**الإصلاح:** اطلب طبقات واعية بالتخزين المؤقت:

> رتِّب الطبقات من الأقل تغيرًا إلى الأكثر تغيرًا: انسخ ملف الاعتماديات وثبِّته في طبقته الخاصة *قبل* نسخ مصدر التطبيق، حتى يُعيد تغيير الكود استخدام الاعتماديات المُخزَّنة. أبقِ تثبيت الاعتماديات منفصلًا عن نسخ المصدر. تأكد من أن تغيير سطر واحد في الكود لا يُعيد تثبيت الاعتماديات.

### Cursor: أسرار مدمجة وإيقاف سلس ضائع

عند تعديل Dockerfile داخل السطر، يميل Cursor إلى توصيل الإعدادات بطريقة محلية للتعديل — `COPY .env .` أو `ARG`/`ENV` بقيمة سر "لجعلها قابلة للتكوين"، وصيغة shell في `CMD`/`ENTRYPOINT` — مما يُدمج الأسرار في الطبقات ويُكسر معالجة `SIGTERM`.

**الكشف:** `COPY .env`/`ADD .env`؛ `ARG`/`ENV` يحمل قيمة سر فعلية؛ أسرار مرئية في `docker history`؛ صيغة shell `CMD uvicorn ...` (ليست صيغة exec بمصفوفة JSON)؛ لا معالجة إشارات/إيقاف سلس.

**الإصلاح:** اطلب أسرار في وقت التشغيل وentrypoint بصيغة exec:

> لا تضع أسرارًا في الصورة — لا `COPY .env`، لا `ARG`/`ENV` لأسرار. تُحقَن الأسرار في وقت التشغيل عبر env/أسرار مُركَّبة. استخدم صيغة exec (`CMD ["uvicorn", ...]`) ليكون التطبيق PID 1 ويستقبل `SIGTERM` للإيقاف السلس. تحقق من أن `docker history` لا يُظهر أي سر.

## أفضل الممارسات

**ثبِّت قاعدة نحيفة وأعد بناء الترقيات بوعي.** `python:3.12-slim`، أبدًا `latest`. صورتك لا تكون قابلة للتكرار إلا إذا كانت قاعدتها ثابتة؛ رقِّ التثبيت كتغيير مُراجَع، لا بصمت.

**multi-stage دائمًا، للاعتماديات المُجمَّعة/المُثبَّتة.** ابنِ في مرحلة ثقيلة، اشحن مرحلة runtime نحيفة تحوي الـ artifact فقط. إنها الرافعة الأكبر على الحجم وسطح الهجوم معًا.

**رتِّب الطبقات للتخزين المؤقت؛ افصل الاعتماديات عن المصدر.** انسخ وثبِّت ملف الاعتماديات أولًا، وانسخ المصدر آخرًا. أبقِ الخطوات البطيئة والمستقرة في البداية ليبقى التكرار سريعًا.

**`USER` بصلاحيات غير root، دائمًا.** أنشئ مستخدمًا مخصصًا وانتقل إليه. سطران، وهو متطلب إنتاجي — اقرنه بمستخدم غير root من جانب المضيف من الفصل 01.

**الأسرار في وقت التشغيل، أبدًا في طبقة.** احقن عبر env/أسرار مُركَّبة؛ أبقِ `.env` خارج السياق بـ `.dockerignore`. تحقق بـ `docker history` أنه لا يوجد سر مدمج.

**أضف `.dockerignore` و`HEALTHCHECK` واستخدم صيغة exec في `CMD`.** صغيرة وعالية الأثر: `.dockerignore` يُقلِّص السياق ويمنع التسربات؛ فحص الصحة يعطي الجاهزية؛ صيغة exec تعطي إيقافًا سلسًا. وسِّم الصور بشكل غير قابل للتغيير (git SHA) لتكون الصورة قابلة للتتبُّع إلى commit.

## الأنماط المضادة (Anti-Patterns)

**صورة "حوض المطبخ" (The Kitchen-Sink Image).** قاعدة ممتلئة، لا multi-stage، سلسلة الأدوات بأكملها مُشَحنة — صورة 1.5 جيجابايت لتطبيق صغير. العلامة: `FROM python`/`node` (ليست نحيفة)، مرحلة واحدة، مئات الميجابايتات في `docker image ls`.

**"كاسر التخزين المؤقت" (The Cache-Buster).** المصدر يُنسَخ قبل الاعتماديات، فكل بناء يُعيد تثبيت كل شيء. العلامة: `COPY . .` فوق `pip install`/`npm ci`؛ بناءات CI تستغرق دقائق لتغيير سطر واحد.

**الحاوية ذات root (The Root Container).** لا `USER`، فالتطبيق يعمل كـ root داخل الحاوية. العلامة: لا سطر `USER`؛ `whoami` داخل الحاوية يُرجع `root`.

**السر المدمج (The Baked Secret).** سر يُنسَخ (`COPY`) أو يُمرَّر كـ `ARG` داخل طبقة، يبقى في سجل الصورة إلى الأبد. العلامة: `COPY .env`؛ أسرار مرئية في `docker history`؛ "دوَّرنا المفتاح لكنه لا يزال في الصورة القديمة."

**البناء بدون سياق (The Contextless Build).** لا `.dockerignore`، فـ `.git`/`node_modules`/`.venv`/`.env` تُرسَل كسياق — بناءات بطيئة وملفات محلية مُسرَّبة. العلامة: سياق بناء ضخم، `.env` محلي داخل الصورة.

**صورة اللقطة (The Snapshot Image).** صورة تُبنى مرة واحدة وتُعدَّل يدويًا بـ `docker exec`/`docker commit` بدلًا من إعادة بنائها من Dockerfile — غير قابلة للتكرار وغير موثَّقة. العلامة: صور لا تقابل أي Dockerfile؛ "لا تُعد بنائها، قمنا بتعديلها مباشرةً."

## شجرة القرار

"أنا أُحوِّل خدمة إلى حاوية (أو أراجع Dockerfile) — ما الذي يجب أن يتحقق؟"

```
BASE IMAGE
  Is it pinned AND slim?  (python:3.12-slim, not python / python:latest)
     no → pin a specific slim tag. latest = non-reproducible; full = bloat + CVEs.

BUILD SHAPE
  Does it compile/install dependencies (C ext, node build, etc.)?
     yes → MULTI-STAGE: builder (toolchain) → runtime (slim, COPY --from only the output).
     no  → single slim stage is fine.

LAYER ORDER
  Is the dependency manifest copied + installed BEFORE the source?
     no → reorder. deps (slow, stable) first; source (fast, volatile) last → cache survives.

CONTEXT
  Is there a .dockerignore excluding .git / deps / caches / .env ?
     no → add one. prevents bloated context AND baking a local .env into the image.

SECURITY
  Is there a non-root USER before CMD?          no → add a user, drop to it.
  Are secrets injected at RUNTIME (not COPY/ARG)? no → move them out; check docker history.

RUNTIME
  Exec-form CMD (["cmd","arg"]) for PID-1 / SIGTERM?   no → convert from shell form.
  A HEALTHCHECK hitting a real readiness endpoint?      no → add one.

VERIFY
  docker image ls → is the size sane (tens–low-hundreds of MB, not GB)?
  docker history  → no secret in any layer?
  one-line code change → rebuilds WITHOUT reinstalling deps?
     all yes → production-ready. any no → fix before it ships.
```

## قائمة التحقق

### قائمة تحقق التطبيق

- [ ] الصورة الأساسية وسم **نحيف مُثبَّت** (`python:3.12-slim`)، أبدًا `latest`/ممتلئة.
- [ ] بناء **multi-stage**: سلسلة الأدوات في مرحلة builder، ن artifact فقط يُنسَخ إلى مرحلة runtime نحيفة.
- [ ] ملف الاعتماديات يُنسَخ ويُثبَّت **قبل** مصدر التطبيق (ترتيب التخزين المؤقت).
- [ ] ملف **`.dockerignore`** يستبعد `.git` ومجلدات الاعتماديات وذاكرة التخزين المؤقت و`.env`.
- [ ] **`USER`** بصلاحيات غير root يُنشَأ ويُنتقل إليه قبل `CMD`.
- [ ] الأسرار تُحقَن في **وقت التشغيل** (env/مُركَّبة)، أبدًا تُنسَخ (`COPY`) أو تُمرَّر كـ `ARG` في طبقة.
- [ ] `CMD` تستخدم **صيغة exec**؛ و**`HEALTHCHECK`** يستهدف endpoint جاهزية حقيقي.

### قائمة تحقق البنية

- [ ] عملية/مسؤولية واحدة لكل حاوية؛ تركيب الخدمات المتعددة يُترَك لـ Compose (الفصل 03).
- [ ] الصور تُوسم **بشكل غير قابل للتغيير** (git SHA)، قابلة للتتبُّع إلى الـ commit الذي بناها.
- [ ] تثبيتات الصورة الأساسية والاعتماديات تُرقَّى كتغييرات مُراجَعة، لا بصمت.
- [ ] Dockerfile يعيش في المستودع ويُخضَع لمراجعة الكود كمصدر.

### قائمة تحقق مراجعة الكود

- [ ] لا `FROM ...:latest` أو قاعدة ممتلئة؛ لا بناء بمرحلة واحدة يُشحن سلسلة الأدوات.
- [ ] لا `COPY . .` قبل تثبيت الاعتماديات (راقب Dockerfiles التي يولِّدها الذكاء الاصطناعي).
- [ ] لا غياب لـ `USER` (حاوية بـ root)؛ لا `COPY .env`/سر `ARG` (سر مدمج).
- [ ] لا صيغة shell في `CMD` حيث يهم الإيقاف السلس؛ وجود `HEALTHCHECK`.
- [ ] تم فحص `docker history` و`docker image ls` (لا سر مدمج؛ حجم معقول).

### قائمة تحقق النشر

- [ ] الصورة التي تعمل في الإنتاج هي **الصورة بالضبط** المبنية والمُفحَصة في CI (بـ digest/SHA)، لا تُعاد بناؤها على الصندوق.
- [ ] حجم الصورة وعدد الطبقات معقولان (دفع/سحب سريع عند النشر والتوسعة).
- [ ] فحص ثغرات (مثل `docker scout`/Trivy) يعمل على الصورة في CI (المرحلة 9 تُحكِّم هذا).
- [ ] الحاوية تعمل للقراءة فقط حيث أمكن ومع سياسة إعادة تشغيل (الفصل 03).

## التمارين

**1. تقليص صورة منتفخة.** ابدأ من Dockerfile ساذج بمرحلة واحدة بـ `FROM python` و`COPY . .` قبل التثبيت ولا `USER`. حوِّله إلى multi-stage على قاعدة نحيفة مُثبَّتة، وأصلح ترتيب الطبقات، وأضف مستخدمًا غير root و`.dockerignore`، وقِس الحجم قبل/بعد بـ `docker image ls`. الـ artifact هما الـ Dockerfileان وفرق الحجم (توقَّع تخفيضًا بمقدار 5–10×).

**2. أثبت أن ترتيب التخزين المؤقت مهم.** بالـ Dockerfile المُصلَح، غيِّر سطرًا واحدًا من كود التطبيق وأعد البناء؛ تأكد من أن طبقة تثبيت الاعتماديات مُعاد استخدامها (`CACHED` في مُخرَج البناء). ثم انقل `COPY . .` فوق التثبيت، أجرِ نفس التغيير، ولاحظ أن كل الاعتماديات تُعاد تثبيتها. الـ artifact هما سجلَّا البناء يُظهران فرق التوقيت.

**3. اصطد سرًا مدمجًا.** عن قصد، اعمل `COPY .env` في صورة، وابنِها، ثم استخدم `docker history` وفُكَّك طبقة لاستخراج السر من الصورة المدفوعة — مُثبتًا لماذا يُعَد دمج الأسرار تسرُّبًا حتى بعد `rm` لاحق. ثم أصلحها إلى حقن في وقت التشغيل وتأكد من أن `docker history` نظيف. الـ artifact هو الاستخراج والـ Dockerfile المُصلَح.

## قراءات إضافية

- **وثائق Docker — "Best practices for building images" و"Multi-stage builds"** (docs.docker.com) — المصدر المرجعي الموثوق لتخزين الطبقات مؤقتًا، وmulti-stage، والصور النحيفة؛ يُعزِّز كل قرار في هذا الفصل.
- **وثائق Docker — Dockerfile reference** (docs.docker.com) — الدلالات الدقيقة لـ `COPY` مقابل `ADD`، وصيغة exec مقابل shell، و`HEALTHCHECK`، و`USER` التي يعتمد عليها هذا الفصل.
- **"Docker Deep Dive" لـ Nigel Poulton** — أوضح نموذج ذهني كامل للصور والطبقات وnamespaces، والتمييز بين الحاوية والـ VM بالعمق الذي يضغطه هذا الفصل.
- **صور Google الـ distroless وأدلة Snyk/"Docker security"** (github.com/GoogleContainerTools/distroless) — الخطوة التالية لصور runtime مُحكَّمة وصغيرة عندما لا تكون slim صغيرة بما يكفي.
- **المرحلة 7، الفصل 03 — Docker Compose والبيئات متعددة الخدمات** — الخطوة التالية: ربط هذه الصور (الخلفية، الواجهة الأمامية، Postgres، Redis، Nginx) في نظام تشغيل واحد قابل للتكرار للتطوير والإنتاج.
