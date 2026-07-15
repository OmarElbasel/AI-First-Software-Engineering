# State Management

## Introduction

يُعدّ "state management" الموضوع الأكثر عُرضة للإفراط في التعقيد في عالم الـ frontend،
لأن العبارة توحي بمشكلة كبيرة واحدة تُحلّ بأداة كبيرة واحدة — وهو
مخزن global يضمّ كل شيء. الواقع الذي يعلّمه هذا الفصل هو العكس تمامًا:
**هناك عدة أنواع متميزة من الـ state، لكل منها موطنه الصحيح، ومعظم ما تلجأ إليه الفرق لاحتواءه في مخزن global لا ينتمي إليه أصلًا.** المهارة ليست في اختيار مكتبة state؛ بل في تصنيف كل قطعة state وتوجيهها إلى حيث تنتمي.

الأنواع:

- **Server state** — البيانات المُجلوبة من الـ backend. تنتمي إلى React Query
  (الفصل 04)، وليس إلى مخزن client. معظم "state" في الشاشات المعتمدة على البيانات هو من هذا النوع.
- **URL state** — عوامل التصفية (filters)، والترتيب (sort)، والصفحات (pagination)، والتبويب المحدد، واستعلام البحث.
  تنتمي إلى URL، حتى تكون قابلة للمشاركة والإضافة إلى المفضلة، وتبقى بعد التحديث،
  وتعمل مع زر الرجوع.
- **Local (UI) state** — هل هذه القائمة المنسدلة مفتوحة، هل هذا الصف موسّع. تنتمي إلى
  `useState`، متجاورة مع المكوّن (colocated).
- **Form state** — القيم التي يتم تحريرها في نموذج. لها أدواتها الخاصة
  (الفصل 06).
- **Global client state** — حالة UI صالحة على مستوى التطبيق بأكمله، مشتركة بين مكوّنات بعيدة:
  الـ theme، والـ client-side session، وmodal عام. هذا هو النوع *الوحيد*
  الذي يُستخدم من أجله مخزن global — وهو جزء صغير من state التطبيق.

بمجرد أن تُصنّف بشكل صحيح، فإن "state management" يذوب إلى حد كبير: server state
من مسؤولية React Query، وURL state هو مسؤولية الـ URL، والـ local state هو `useState`،
والشريحة المتبقية — UI state عام حقيقي — لا تحتاج إلا إلى أداة صغيرة وبسيطة.
الخطأ، والوضع الافتراضي لدى AI، هو تخطي التصنيف وإلقاء كل شيء في مخزن global واحد.

## Why It Matters

يُعدّ التمركز المفرط للـ state من أكثر أخطاء هندسة الـ frontend شيوعًا وتكلفةً.
يؤدي مخزن global يضمّ بيانات الخادم وحالة التصفية وحالة الـ UI المحلية معًا
إلى تشابك تلمسه كل شاشة، ويشكّل كل تغيير خطر إعادة عرض واسعة،
وتصبح بيانات الخادم قديمة دون تخزين مؤقت، ولا يعكس الـ URL ما ينظر إليه المستخدم.
إنه الإصدار الـ frontend من "big ball of mud"، ويزداد سوءًا مع كل ميزة جديدة.

يؤدي تصنيف الـ state بشكل صحيح إلى تجنّب إخفاقات محددة وملموسة:

- **Server state في مخزن يصبح قديمًا وبدون تخزين مؤقت.** البيانات المُجلوبة والمُدارة يدويًا في
  مخزن global ليس لها تخزين مؤقت، أو إزالة تكرار، أو إبطال (invalidation) — وهي المشكلات
  التي حلّها الفصل 04 باستخدام React Query، لتعود من جديد. بيانات الخادم لا تنتمي إلى مخزن client.
- **URL state في state مكوّن يكسر المشاركة والتنقّل.** إذا وضعت التصفية، أو الترتيب، أو الصفحة، أو التبويب المحدد في `useState`
  فلن يستطيع المستخدم مشاركة الرابط، ولا إضافة العرض إلى المفضلة، وسيفقده عند التحديث،
  ولن يستعيده زر الرجوع. الـ URL *هو* state لهذه العناصر؛ وعدم استخدامه يُعدّ تراجعًا حقيقيًا في تجربة المستخدم.
- **State عالي التردد في Context يسبّب عواصف إعادة العرض.** يعيد React Context
  عرض *كل* مستهلك له كلما تغيّرت قيمته، لذا فإن وضع state يتغيّر بسرعة
  (إدخال نموذج، قيمة حيّة) في Context يُحدث تقطّعًا في الشجرة الفرعية بأكملها. الـ Context مخصّص للقيم
  منخفضة التردد، على غرار dependency injection.
- **مخزن ثقيل لحاجة خفيفة هو تعقيد ميت.** اللجوء إلى Redux
  عندما يحتوي التطبيق على القليل من UI state عام حقيقي يضيف boilerplate ومفاهيم
  دون أي فائدة (الإفراط في الهندسة في المرحلة 1، الفصل 07).

البُعد المتعلق بالـ AI: يلجأ المساعدون افتراضيًا إلى مخزن global (غالبًا Redux)،
لأن "state management" يطابق هذا النمط في بيانات تدريبهم — فيضعون
بيانات الخادم، والحالة المناسبة للـ URL، والـ local state كلها في مخزن واحد، ويُسيئون استخدام
Context مع state عالي التردد. النتيجة هي واجهة أمامية مفرطة التمركز، وقديمة، وغير قابلة للمشاركة،
تعاني من مشكلات إعادة العرض.

## Mental Model

بالنسبة لكل قطعة state، السؤال هو *ما نوعها؟* — والإجابة توجّهها إلى موطنها:

```
   WHAT KIND OF STATE IS THIS?

   ┌─ Data from the backend? ─────────► SERVER STATE  → React Query (Chapter 04).
   │                                     (NOT a client store — no caching there.)
   │
   ├─ A filter / sort / page / tab / ──► URL STATE     → the URL (searchParams).
   │  search query the user navigates?    (shareable, bookmarkable, survives refresh,
   │                                        back button works.)
   │
   ├─ Values being edited in a form? ──► FORM STATE    → form tools (Chapter 06).
   │
   ├─ Local UI (is this open/expanded)? ► LOCAL STATE  → useState, colocated (Chapter 01).
   │
   └─ Genuinely APP-WIDE UI state shared ► GLOBAL CLIENT STATE → the smallest tool that works:
      across distant components?           low-frequency → Context; complex/frequent → a small store.
      (theme, client session, global modal)  ← the ONLY kind a store is for, and it's SMALL.

   THE LADDER (reach only as far as you need):
     useState ──► lift state up ──► Context (low-frequency) ──► a state library (complex/high-frequency)
```

ثلاثة مبادئ تشكّل جوهر الفصل:

**صنّف قبل أن تلجأ إلى أداة.** أول خطوة لأي state هي تسمية نوعه،
لأن النوع يحدّد الموطن. معظم state في شاشة حقيقية هو server state
(من مسؤولية React Query) أو URL state (من مسؤولية الـ URL)؛ والكمية
التي هي global client state حقًا صغيرة. "State management" هو في معظمه مسألة تصنيف.

**Global client state هو الاستثناء، ويبقى صغيرًا.** المخزن العام مخصّص
لمجموعة state ضيّقة من الحالات الصالحة حقًا على مستوى التطبيق بأكمله والمشتركة بين مكوّنات بعيدة — مثل الـ theme،
والـ client session، وfeature flags، وmodal عام. ليس لبيانات الخادم، ولا لـ URL state،
ولا لـ state الذي يستطيع مكوّن وجاره مشاركته عن طريق الرفع. أنت بحاجة إلى
global state أقل بكثير مما توحي به عبارة "state management".

**اصعد في السلّم بقدر الحاجة فقط.** ابدأ بـ `useState` محلي؛ ارفعه إلى
أب مشترك عند المشاركة (الفصل 01)؛ استخدم Context للقيم الصالحة على مستوى التطبيق ومنخفضة التردد
(dependency injection: theme، المستخدم الحالي)؛ لا تلجأ إلى مكتبة state إلا عندما يكون
global state معقدًا أو يتغيّر بتردد يجعل سلوك إعادة العرض في Context
مؤلمًا. لا تبدأ من القمة.

تعريف عملي:

> **State management هو في معظمه تصنيف: وجّه server state إلى React Query، وURL state إلى الـ URL، وlocal state إلى `useState`، وform state إلى أدوات النماذج، ولا توجّه إلى المخزن العام سوى UI state صالح حقًا على مستوى التطبيق — ويبقى صغيرًا. الخطأ هو تخطّي التصنيف وتمركز كل شيء.**

## Production Example

تحتوي شاشة الفواتير في **Invoicely** على عدة قطع من الـ state، والدرس الكامل
هو أنها تنتمي إلى أماكن *مختلفة*:

- بيانات **الفواتير** → server state → React Query (الفصل 04)؛
- **status filter**، وsort، وpage → URL state → الـ URL، ليكون العرض المُصفّى
  قابلًا للمشاركة ويبقى بعد التحديث؛
- هل **صف معيّن موسّع** → local state → `useState` في الصف؛
- **الـ theme والشريط الجانبي المطوي** → UI state صالح حقًا على مستوى التطبيق → مخزن عام صغير أو Context.

سنوجّه كلًّا منها إلى موطنه الصحيح، ونقارنه بالنمط السيئ الذي
يميل المساعد إلى إنتاجه: مخزن Redux عام واحد يضمّ بيانات الفواتير،
والـ filters، والـ pagination، *و* علامات expanded-row — مفرط التمركز، وقديم،
وغير قابل للمشاركة. النقطة ليست في اختيار المخزن؛ بل في أن معظم هذا الـ state
لا ينبغي أن يكون في مخزن أصلًا.

## Folder Structure

```
web/src/
├── app/(app)/invoices/page.tsx      # reads filter/sort/page from URL searchParams
├── features/invoices/
│   ├── queries.ts                   # SERVER state (React Query, Chapter 04)
│   └── InvoiceRow.tsx               # LOCAL state (useState) for "expanded"
├── lib/
│   ├── url-state.ts                 # helpers for reading/writing URL state
│   └── ui-store.ts                  # small GLOBAL store: theme, sidebar (app-wide UI only)
└── app/providers.tsx                # Context for the client session (low-frequency DI)
```

سبب هذا الشكل: كل نوع من الـ state يعيش مع الأداة المناسبة له — server state في
هوكات الـ query، وURL state يُقرأ من `searchParams`، وlocal state في المكوّن، و
مخزن عام *صغير* لـ UI الخاص بالتطبيق بأكمله. لا يوجد "مخزن" واحد يضمّ كل شيء.

## Implementation

**URL state — عوامل التصفية، والترتيب، والصفحة (`page.tsx`).** يعيش هذا في الـ URL، ليكون العرض قابلًا
للمشاركة، وقابلًا للإضافة إلى المفضلة، وصامدًا أمام التحديث، ويستطيع الخادم قراءته للعرض.

```tsx
// Server Component reads URL state from searchParams — the filtered view IS the URL.
export default async function InvoicesPage({
  searchParams,
}: { searchParams: { status?: string; sort?: string; page?: string } }) {
  const filter = {
    status: searchParams.status ?? "all",
    sort: searchParams.sort ?? "recent",
    page: Number(searchParams.page ?? 1),
  };
  const invoices = await getInvoices(filter);       // server state, keyed by URL state
  return <InvoicesClient initial={invoices} filter={filter} />;
}
```

```tsx
// Client: changing a filter updates the URL (not useState) — shareable, back-button works.
"use client";
import { useRouter, useSearchParams, usePathname } from "next/navigation";

function StatusFilter() {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  function setStatus(status: string) {
    const next = new URLSearchParams(params);
    next.set("status", status);
    next.delete("page");                            // reset pagination on filter change
    router.push(`${pathname}?${next}`);             // URL is the source of truth
  }
  // ...
}
```

**Local state — متجاور في المكوّن (`InvoiceRow.tsx`).** "هل هذا الصف موسّع"
لا يعنى أحدًا سواه؛ فهو يعيش في الصف.

```tsx
"use client";
import { useState } from "react";

function InvoiceRow({ invoice }: { invoice: Invoice }) {
  const [expanded, setExpanded] = useState(false);   // LOCAL UI state — colocated
  // ...
}
```

**Global client state — صغير، UI خاص بالتطبيق بأكمله فقط (`ui-store.ts`).** الـ theme والشريط الجانبي صالحان حقًا
على مستوى التطبيق بأكمله ومشتركان بين مكوّنات بعيدة، لذا يناسبهما مخزن *صغير*. لاحظ
ما ليس هنا: لا توجد بيانات فواتير، ولا عوامل تصفية.

```tsx
"use client";
import { create } from "zustand";

// GLOBAL client state — ONLY genuinely app-wide UI. Small on purpose.
export const useUiStore = create<{
  theme: "light" | "dark";
  sidebarCollapsed: boolean;
  toggleTheme: () => void;
  toggleSidebar: () => void;
}>((set) => ({
  theme: "light",
  sidebarCollapsed: false,
  toggleTheme: () => set((s) => ({ theme: s.theme === "light" ? "dark" : "light" })),
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
}));
```

**Context لـ DI منخفض التردد (`providers.tsx`).** يتم ضبط الـ client session مرة واحدة ونادرًا ما يتغيّر — مما يجعله
قيمة Context مثالية (dependency injection)، وليس شيئًا يُعيد عرض المستهلكين باستمرار.

```tsx
"use client";
import { createContext, useContext } from "react";

const SessionContext = createContext<Session | null>(null);
export const useSession = () => useContext(SessionContext);   // low-frequency value

export function SessionProvider({ session, children }: { session: Session; children: React.ReactNode }) {
  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>;
}
```

**النمط السيئ — كل شيء في مخزن عام واحد.** كل سطر هنا هو
تصنيف خاطئ:

```tsx
// ANTI-PATTERN: one global store holding EVERYTHING
const useStore = create((set) => ({
  invoices: [],          // SERVER state → belongs in React Query (stale, uncached here)
  statusFilter: "all",   // URL state → belongs in the URL (un-shareable here)
  currentPage: 1,        // URL state → belongs in the URL
  expandedRows: {},      // LOCAL state → belongs in the component
  theme: "light",        // ← the ONLY thing that genuinely belongs in a global store
  // ...50 more fields, every screen coupled to this store
}));
```

الفرق هو جوهر الفصل: عند التوجيه الصحيح، تكون بيانات الفواتير مُخزّنة مؤقتًا وطازجة (React Query)،
ويكون العرض المُصفّى URL قابلًا للمشاركة، وتكون state الصف محلية ومعزولة، ويضمّ المخزن العام
الـ theme والشريط الجانبي فقط. عند إلقائها في مخزن واحد، تكون بيانات الخادم قديمة وبدون تخزين مؤقت،
ولا يمكن مشاركة العرض أو إضافته إلى المفضلة، وكل شاشة مرتبطة بمخزن عملاق،
وتنتشر التغييرات على شكل إعادة عرض واسعة. الـ state هو نفسه؛
ترتيب واحد فقط هو الذي يقبل التوسّع.

## Engineering Decisions

تُحدّد خمس قرارات معنى state management — والقرار الأول يحسم معظمها.

### What kind of state is this?

**الخيارات:** التعامل مع كل الـ state بشكل موحّد (أداة واحدة)، أو تصنيف كل قطعة وتوجيهها.

**المفاضلات:** أداة موحّدة (عادة مخزن global) هي بسيطة مفاهيميًا وخاطئة
— فهي تُجبر server state وURL state وlocal state على الاحتواء في وعاء لم يُبنَ لأي منها،
مما يُفقد التخزين المؤقت، والقابلية للمشاركة، والتجاور. يستغرق التصنيف لحظة تفكير
لكل قطعة ويضع كلًّا منها حيث تعمل.

**التوصية:** صنّف كل قطعة state بحسب نوعها — server / URL / form / local /
global-client — ووجّهها إلى موطن ذلك النوع. هذه العادة وحدها تمنع غالبية
مشكلات state management، لأن معظم الـ state يتبين أنه server state أو URL state
لم يكن بحاجة إلى "إدارة" بالمعنى المخزني أصلًا.

### Do you need a global store at all?

**الخيارات:** (1) تبنّي مخزن global مبكرًا؛ (2) إضافته فقط عندما تتراكم global client state حقيقية.

**المفاضلات:** يوفّر التبني المبكر موطنًا جاهزًا لـ state المشتركة ويغريك بوضع
كل شيء فيه (تمركز مفرط). يحافظ الانتظار على بساطة التطبيق ويعني refactor صغيرًا إذا ظهر global state حقيقي — وهو رخيص،
لأنك تعرف حينها بالضبط ما هو global.

**التوصية:** لا تُضف مخزن global حتى يكون لديك app-wide client state حقيقي
لا يستطيع Context التعامل معه براحة — وحتى حينها حافظ عليه صغيرًا. تحتاج معظم التطبيقات إلى
global state أقل بكثير مما هو متوقّع بمجرد توجيه server state (React Query) وURL state (الـ URL)
إلى موطنهما. اللجوء إلى Redux في اليوم الأول عادةً ما يكون سابقًا لأوانه.

### Context or a state library for global state?

**الخيارات:** (1) React Context؛ (2) مكتبة state (Zustand/Redux/Jotai).

**المفاضلات:** الـ Context مدمج ومثالي للقيم منخفضة التردد، على غرار dependency injection
(theme، session، config) — لكنه يُعيد عرض كل المستهلكين عند كل تغيّر، لذا فهو
خاطئ لـ state عالي التردد. توفّر مكتبة state اشتراكات انتقائية (يُعيد المستهلكون
العرض فقط للـ slice الذي يستخدمونه) وبنية، بتكلفة dependency.

**التوصية:** Context للقيم منخفضة التردد الصالحة على مستوى التطبيق (theme، session، feature
flags)؛ مكتبة state عندما يكون global state معقدًا أو يتغيّر بتردد يجعل سلوك
"إعادة عرض كل شيء" في Context مؤلمًا. لا تضع أبدًا state يتغيّر بسرعة في Context.

### URL state or component/store state for filters, tabs, pagination?

**الخيارات:** (1) `useState`/مخزن؛ (2) الـ URL (`searchParams`).

**المفاضلات:** `useState`/المخزن سريع ويجعل العرض عابرًا — غير قابل للمشاركة،
وغير قابل للإضافة إلى المفضلة، وضائع عند التحديث، وغير مرئي لزر الرجوع. يجعل الـ URL العرض
مواطنًا من الدرجة الأولى قابلًا للربط والتنقّل، ويمكن قراءته على الخادم، بتكلفة بعض
التمديدات (plumbing) لمزامنة الـ URL.

**التوصية:** ضع state التنقّل — عوامل التصفية، والترتيب، والصفحات، والتبويب المحدد، واستعلام البحث — في الـ URL. إنه قابل للمشاركة، وقابل للإضافة إلى المفضلة، وصامد أمام التحديث، ولطيف مع زر الرجوع، وقابل للقراءة من الخادم. أبقِ UI العابر حقًا (hover، قائمة مفتوحة) في local state. "هل سيودّ المستخدم مشاركة هذا العرض أو إضافته إلى المفضلة؟" — إذا كانت الإجابة نعم، فهو URL state.

### Which state library, if you need one?

**الخيارات:** Zustand (بسيطة)، وRedux Toolkit (منظّمة، باتفاقيات)، وJotai/atoms
(ذرية)، وغيرها.

**المفاضلات:** Zustand بسيطة وغير موجّهة بالرأي — رائعة لقدر صغير من global
state. يقدّم Redux Toolkit بنية، وdevtools، واتفاقيات تساعد في state كبير ومعقد وعلى نطاق الفريق،
بتكلفة boilerplate. يناسب النموذج الذري لـ Jotai state الدقيق والمشتق. الاختيار بالحجم الخاطئ هو إما boilerplate لا تحتاجه أو بنية قليلة جدًا لـ state معقد حقًا.

**التوصية:** ابدأ بأبسط ما يناسب — Zustand للقدر المعتاد الصغير من
global UI state؛ Redux Toolkit فقط عندما يكون global state كبيرًا ومعقدًا حقًا
بحيث يستفيد من بنيته وأدواته. لكن تأكّد أولًا أن الـ state هو global client state حقيقي
وليس server/URL state في ثوب مختلف — اختيار المكتبة يأتي بعد التصنيف، وهو أقل أهمية بكثير منه.

## Trade-offs

تُقايِم خيارات state management بين البساطة، والقابلية للمشاركة، والأداء، والتوازن
تدور معظمه حول عدم الإفراط في المدّ.

**التصنيف يقايض لحظة تفكير بالهندسة الصحيحة.** توجيه كل قطعة state
إلى موطنها هو تفكير استباقي أكثر من "ضعه في المخزن"، ويعيد إليك
التخزين المؤقت (server state)، والقابلية للمشاركة (URL state)، والعزل (local state)، ومخزنًا صغيرًا.
التكلفة ضئيلة؛ والعائد يتراكم مع نمو التطبيق.

**المخزن العام يقايض boilerplate بمشاركة حقيقية.** عندما يكون state صالحًا حقًا على مستوى التطبيق بأكمله،
يكون المخزن هو الأداة الصحيحة ويستحق ما يفرضه من overhead؛ وعندما لا يكون كذلك،
يكون المخزن تعقيدًا ميتًا ومغناطيسًا للاقتران. لا تؤتي المقايضة ثمارها إلا لـ global state حقيقي — ولهذا يأتي
سؤال "هل تحتاجه أصلًا؟" أولًا.

**Context يقايض البساطة بسلوك إعادة العرض.** الـ Context مدمج ومثالي
للقيم منخفضة التردد، وسلوك "إعادة عرض كل المستهلكين" يجعله خاطئًا لـ
state عالي التردد. المقايضة جيدة داخل مساحتها وسيئة خارجها — والعلاج هو
استخدام Context فقط للقيم منخفضة التردد التي يناسبها.

**URL state يقايض قليلًا من التمديدات بتجربة مستخدم حقيقية.** مزامنة state مع الـ URL أكثر عملًا قليلًا من `useState`
وتُكسبك عروضًا قابلة للمشاركة، والإضافة إلى المفضلة، والتنقّل. بالنسبة لـ state التنقّل
يكون مكسب تجربة المستخدم حاسمًا؛ وبالنسبة لـ UI العابر حقًا لا يستحق التمديد — طابِق
الاختيار مع ما إذا كان العرض يستحق المشاركة.

## Common Mistakes

**كل شيء في مخزن عام.** بيانات الخادم، وURL state، وlocal state كلّها مركزة —
بيانات خادم قديمة، وعروض غير قابلة للمشاركة، واقتران واسع، وموجة إعادة عرض. الحل: صنّف ووجّه؛
يحمل المخزن global UI state صالحًا على مستوى التطبيق فحسب.

**Server state في مخزن client.** بيانات مُجلبة تُدار يدويًا في Redux/Zustand — مشكلات التخزين المؤقت
وإبطال البيانات التي حلّها الفصل 04 تعود من جديد. الحل: React Query لـ server state.

**state تنقّل في `useState`.** عوامل التصفية، والترتيب، والصفحات، والتبويبات في state مكوّن — غير
قابلة للمشاركة، تضيع عند التحديث، وزر الرجوع معطّل. الحل: ضعها في الـ URL.

**state عالي التردد في Context.** قيم تتغيّر بسرعة في Context provider، فتُعيد عرض
كل المستهلكين. الحل: Context للقيم منخفضة التردد فقط؛ local state أو مخزن مع
selectors للتغيّرات المتكررة.

**مخزن ثقيل لحاجة خفيفة.** Redux (مع boilerplate الخاص به) لتطبيق يحتوي على القليل من
global state. الحل: استخدم أبسط أداة (غالبًا Context أو Zustand)، أو لا شيء — بعد التأكّد
من أن الـ state هو global حقًا.

**Prop drilling بدلًا من الموطن الصحيح.** تمرير state عبر طبقات كثيرة لأنه لم يُصنّف —
غالبًا هو server state، أو URL state، أو قيمة Context. الحل: وجّهه إلى
موطنه الصحيح بدلًا من الحفر بالـ props.

## AI Mistakes

يطابق "state management" نمط "global store" في بيانات التدريب، فيُفرط المساعدون
افتراضيًا في التمركز ويتخطون التصنيف الذي يجعل المشكلة قابلة للحل.
راجع كود الـ state للتحقّق من أن كل قطعة في الموطن المناسب لها.

### Claude Code: centralizing everything in a global store

عند طلب "إدارة state" أو "إضافة state management"، يلجأ Claude Code إلى مخزن global
(غالبًا Redux) ويضع بيانات الخادم، وعوامل التصفية، والصفحات، وعلامات UI المحلية فيه، لأن
هذا هو شكل "state management" في بيانات تدريبه. يصبح المخزن
مُلتقًى لكل شيء، وتصبح بيانات الخادم قديمة، وكل شاشة مرتبطة به.

**الاكتشاف:** مخزن global يضمّ بيانات خادم مُجلبة، أو state تصفية/ترتيب/صفحات، أو
علامات UI لكل مكوّن؛ إدخال Redux/مخزن لتطبيق يحتوي على القليل من global state
حقيقي؛ state يستحق `useState` يعيش في مخزن global.

**الإصلاح:** اشترط التصنيف:

> لا تضع كل شيء في مخزن global. صنّف كل قطعة state: بيانات الخادم → React Query (الفصل 04)؛ عوامل التصفية/الترتيب/الصفحات/التبويبات → الـ URL؛ UI محلي → `useState`؛ UI صالح حقًا على مستوى التطبيق (theme، session) → مخزن global صغير فقط. معظم هذا لا ينتمي إلى مخزن.

### GPT: high-frequency state in Context

تلجأ نماذج عائلة GPT إلى React Context لمشاركة state على نطاق واسع، بما في ذلك القيم
التي تتغيّر بسرعة (حقل نموذج، عداد حي، موضع الفأرة)، لأن الـ Context هو آلية
"مشاركة state" المدمجة — دون مراعاة كون الـ Context يُعيد عرض كل مستهلك عند كل
تغيّر، مما يُحدث تقطّعًا في الشجرة الفرعية بأكملها.

**الاكتشاف:** Context provider تتغيّر قيمته بشكل متكرر ويُستهلَك عبر شجرة فرعية كبيرة؛
تقطّع/إعادة عرض مرئية مرتبطة بتحديث في Context؛ state نموذج أو إدخال مرفوع إلى
Context.

**الإصلاح:** طابِق الأداة مع التردد:

> يُعيد Context عرض كل المستهلكين عند كل تغيّر في القيمة، لذا استخدمه فقط للقيم منخفضة التردد (theme، session، config). بالنسبة لـ state مشترك يتغيّر بشكل متكرر، أبقه محليًا، أو استخدم
> مكتبة state ذات اشتراكات انتقائية حتى لا يُعيد العرض إلا المكوّنات التي تستخدم slice معيّنًا.

### Cursor: navigational state trapped in component state

عند ربط عوامل التصفية أو التبويبات أو الصفحات بشكل مباشر، يضعها Cursor في `useState`،
لأنها أقصر طريقة محلية لجعل عنصر التحكّم يعمل — فيصبح العرض غير قابل للمشاركة، ولا يصمد أمام
التحديث، ولا يستعيده زر الرجوع.

**الاكتشاف:** state تصفية/ترتيب/صفحات/تبويب-محدد/بحث في `useState` (أو مخزن) بدلًا من الـ URL؛ عرض مُصفّى أو مرقّم لا يتغيّر الـ URL الخاص به أثناء تنقّل المستخدم فيه.

**الإصلاح:** اشترط URL state:

> عوامل التصفية، والترتيب، والصفحات، والتبويب المحدد، واستعلامات البحث هي URL state — ضعها في الـ URL (`searchParams`)، وليس في `useState`، ليكون العرض قابلًا للمشاركة، والإضافة إلى المفضلة، وصامدًا أمام التحديث، ويعمل مع زر الرجوع. أبقِ في local state UI العابر حقًا فقط.

## Best Practices

**صنّف كل قطعة state، ثم وجّهها.** Server → React Query؛ URL/تنقّل →
الـ URL؛ UI محلي → `useState`؛ form → أدوات النماذج (الفصل 06)؛ UI صالح حقًا على مستوى التطبيق → مخزن global
صغير. التصنيف هو الانضباط بأكمله.

**حافظ على global client state صغيرًا، وأضف مخزنًا في وقت متأخر.** المخزن مخصّص لـ UI state
صالح حقًا على مستوى التطبيق فحسب، ويبقى صغيرًا؛ لا تُضف واحدًا إلا عندما تتجاوز
state كهذه ما يستطيع Context التعامل معه. أنت بحاجة إلى global state أقل مما توحي به "state management".

**استخدم Context للقيم منخفضة التردد، ومكتبة للقيم المتكررة/المعقدة.** الـ theme، والـ session،
والـ config في Context؛ مكتبة state (مع اشتراكات انتقائية) عندما يتغيّر global state بشكل متكرر
أو يكون معقدًا. لا تضع أبدًا state عالي التردد في Context.

**ضع state التنقّل في الـ URL.** عوامل التصفية، والترتيب، والصفحات، والتبويبات، والبحث — في
`searchParams`، حتى تكون العروض قابلة للمشاركة، والإضافة إلى المفضلة، وصامدة أمام التحديث، وقابلة للقراءة من الخادم.

**اصعد في السلّم بقدر الحاجة فقط، ولا تنسخ server state.** `useState` → رفع →
Context → مكتبة، بهذا الترتيب من التصعيد؛ لا تنسخ أبدًا بيانات الخادم إلى مخزن
client (الفصل 04). وثّق اتفاقيات تصنيف الـ state في `CLAUDE.md`.

## Anti-Patterns

**The God Store.** مخزن global واحد يضمّ بيانات الخادم، وURL state، وlocal state معًا —
بيانات قديمة، وعروض غير قابلة للمشاركة، واقتران على مستوى التطبيق، وموجة إعادة عرض. العلامة: مخزن يضمّ
عشرات الحقول التي تستوردها كل شاشة.

**Server State in the Store.** بيانات مُجلبة تُدار يدويًا في مخزن client، فتُعيد
مشكلات التخزين المؤقت/الإبطال التي يحلّها React Query. العلامة: ردود API مخزّنة في Redux/Zustand
ومُزامنة يدويًا.

**The Ephemeral View.** state تنقّل (filter/sort/page/tab) في `useState`، فلا يمكن مشاركة
العرض أو إضافته إلى المفضلة ويموت عند التحديث. العلامة: URL مُصفّى لا يتغيّر أبدًا عند التصفية.

**The Context Firehose.** state عالي التردد في Context، فيُعيد عرض كل المستهلكين. العلامة:
Context تتغيّر قيمته بسرعة وشجرة فرعية متقطّعة.

**The Premature Redux.** مخزن ثقيل وboilerplate الخاص به لتطبيق لا يكاد يحتوي على أي global
state. العلامة: إعداد Redux يفوق بكثير حجم global state الحقيقي الذي يحمله.

## Decision Tree

"لديّ قطعة state — أين تعيش؟"

```
WHAT KIND OF STATE IS THIS?
│
├─ Data fetched from the backend? ─────────► SERVER STATE → React Query (Chapter 04).
│
├─ A filter / sort / page / tab / search   ─► URL STATE → the URL (searchParams).
│  the user would share or bookmark?          (shareable, refresh-proof, back button works)
│
├─ Values being edited in a form? ─────────► FORM STATE → form tools (Chapter 06).
│
├─ Local UI (open/expanded/hovered)? ──────► LOCAL STATE → useState, colocated.
│    (need it in a sibling too? ── lift it to the common parent, Chapter 01.)
│
└─ Genuinely APP-WIDE UI state shared ─────► GLOBAL CLIENT STATE (and keep it small):
   across distant components?                  ├─ low-frequency (theme, session)? ─► Context
   (theme, session, global modal, flags)       └─ frequent/complex? ─► a small store (Zustand;
                                                   Redux only if genuinely large & complex)

   Reach up the ladder ONLY as far as the need. Most state never leaves the first two branches.
```

## Checklist

### Implementation Checklist

- [ ] تم تصنيف كل قطعة state (server / URL / form / local / global-client) وتوجيهها إلى ذلك الموطن.
- [ ] بيانات الخادم في React Query، وليس في مخزن client.
- [ ] state التنقّل (filter/sort/page/tab/search) في الـ URL، وليس في `useState`.
- [ ] UI state المحلي متجاور مع `useState`؛ ولا يُرفع إلا عند المشاركة.
- [ ] المخزن العام (إن وُجد) يضمّ app-wide UI state حقيقيًا فقط وهو صغير.
- [ ] الـ Context يضمّ قيمًا منخفضة التردد فقط؛ global state المتكرر/المعقد يستخدم مكتبة مع selectors.

### Architecture Checklist

- [ ] لا يوجد مخزن واحد يضمّ كل شيء؛ الـ state يعيش في مواطن مناسبة لنوعه.
- [ ] لم يُضَف مخزن global إلا لأن app-wide client state حقيقي اقتضى ذلك.
- [ ] اختيار مكتبة الـ state (إن وُجدت) يناسب حجم global state (Zustand مقابل Redux).
- [ ] العروض التي سيودّ المستخدم مشاركتها/إضافتها إلى المفضلة تنعكس في الـ URL.
- [ ] اتفاقيات تصنيف الـ state موثّقة في `CLAUDE.md`.

### Code Review Checklist

- [ ] لا توجد بيانات خادم موضوعة في مخزن client (راقب diffs الخاصة بالـ AI).
- [ ] لا يوجد state تنقّل محبوس في `useState` بدلًا من الـ URL.
- [ ] لا يوجد state عالي التردد في Context.
- [ ] لا يوجد مخزن global مُدخل لـ state هو local أو URL أو server state.
- [ ] لا يوجد prop drilling كان من الممكن أن يُزاله تصنيف صحيح (Context/URL/server).

*(A Deployment Checklist is not applicable to this chapter.)*

## Exercises

**1. صنّف state شاشة.** اذكر كل قطعة state على شاشة الفواتير في Invoicely
وصنّف كلًّا منها (server / URL / local / global-client)، مُسمّيًا موطنها الصحيح. المخرج هو
الجدول؛ والنقطة هي مدى ضآلة ما هو global client state حقًا.

**2. انقل عرضًا إلى الـ URL.** خذ قائمة مُصفّاة/مُرقّمة يكون فيها التصفية والصفحة في
`useState` (اكتب واحدة، أو اطلب من مساعد أن يُولّد "قائمة فواتير قابلة للتصفية") وانقل ذلك
الـ state إلى الـ URL. ثم برهن على المكاسب: رابط قابل للمشاركة، وزر رجوع يعمل، و
state يصمد أمام التحديث. المخرج هو قبل/بعد والسلوكيات المُبرهَن عليها.

**3. أنشِخ مخزن god.** خذ مخزن global يضمّ بيانات الخادم، وعوامل التصفية، وعلامات محلية
(اكتب واحدًا، أو ولّد "أضف Redux state management إلى هذا التطبيق") وأعد هيكلته: بيانات الخادم إلى
React Query، وعوامل التصفية إلى الـ URL، والعلامات المحلية إلى `useState`، تاركًا فقط UI صالحًا حقًا على مستوى التطبيق في
مخزن صغير. المخرج هو قبل/بعد وملاحظة عمّا لم تعد كل شاشة مرتبطة به.

## Further Reading

- **TkDodo — "Working with Zustand" ومقالات React Query حول تقسيم server-state/client-state**
  (tkdodo.eu/blog) — أوضح كتابة حول التمييز المركزي في هذا الفصل: معظم
  "global state" هو server state، وما يتبقى صغير.
- **React documentation — "Managing State"، و"Passing Data Deeply with Context"، و"Scaling Up
  with Reducer and Context"** (react.dev) — الإرشادات الرسمية حول رفع الـ state، ومتى يناسب
  الـ Context، وسلوك إعادة العرض فيه؛ الأساس الذي يقوم عليه السلّم.
- **Zustand documentation** (github.com/pmndrs/zustand) و**Redux Toolkit documentation**
  (redux-toolkit.js.org) — اقرأ كليهما بإيجاز لمعايرة الفرق: بساطة Zustand مقابل
  بنية Redux Toolkit، حتى تستطيع مطابقة الأداة مع حجم global state الحقيقي.
- **"Storing State in the URL"** (ابحث عن كتابات حول `searchParams`/`nuqs` وURL state في
  Next.js) — أنماط عملية لمعاملة الـ URL كمخزن state من الدرجة الأولى، وهو أكثر
  الأفكار التي يُقلَّل استخدامها في إدارة state الـ frontend.
