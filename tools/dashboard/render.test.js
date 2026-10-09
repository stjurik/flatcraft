/* global require, __dirname, process */
"use strict";

// render.test.js — render.js (ADR-042 §10) без браузера: ті самі функції мають
// однаково поводитись під node --test (CI job «Guard-скрипти», контейнер
// оракула на A8) і в браузері. DASH_RENDER_UNDER_TEST дозволяє dash-page.test.sh
// прогнати цей же файл тестів проти мутанта render.js (мутаційні сценарії там).
const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const RENDER_PATH = process.env.DASH_RENDER_UNDER_TEST || path.join(__dirname, "render.js");
const DashRender = require(RENDER_PATH);

const NOW = "2026-09-30T14:00:00Z";

function envelope(overrides) {
  return Object.assign(
    {
      schema_version: 1,
      section: "x",
      title: "Х",
      source: "тест",
      collected_at: "2026-09-30T13:55:00Z",
      interval_s: 300,
      status: "ok",
      origin: "measured",
      data: {},
    },
    overrides,
  );
}

// ─── sectionState ───────────────────────────────────────────────────────────

test("sectionState: свіжий ok — ok", () => {
  assert.equal(DashRender.sectionState(envelope({}), NOW), "ok");
});

test("sectionState: рівно на межі 3×interval_s — ще ok", () => {
  const env = envelope({ collected_at: "2026-09-30T13:45:00Z", interval_s: 300 });
  assert.equal(DashRender.sectionState(env, NOW), "ok");
});

test("sectionState: status ok, але вік старший за 3×interval_s — stale, не ok", () => {
  const env = envelope({ collected_at: "2026-09-30T13:44:59Z", interval_s: 300, status: "ok" });
  assert.equal(DashRender.sectionState(env, NOW), "stale");
});

test("sectionState: явний status stale лишається stale", () => {
  assert.equal(DashRender.sectionState(envelope({ status: "stale" }), NOW), "stale");
});

test("sectionState: status error лишається error навіть зі свіжим collected_at", () => {
  assert.equal(DashRender.sectionState(envelope({ status: "error" }), NOW), "error");
});

test("sectionState: status not_measured лишається not_measured", () => {
  assert.equal(DashRender.sectionState(envelope({ status: "not_measured" }), NOW), "not_measured");
});

test("sectionState: немає env — missing", () => {
  assert.equal(DashRender.sectionState(null, NOW), "missing");
  assert.equal(DashRender.sectionState(undefined, NOW), "missing");
});

test("sectionState: годинник у майбутньому більш ніж на interval_s — не ok", () => {
  const env = envelope({ collected_at: "2026-09-30T14:05:01Z", interval_s: 300 });
  assert.notEqual(DashRender.sectionState(env, NOW), "ok");
});

// ─── sourcesSummary ─────────────────────────────────────────────────────────

test("sourcesSummary: рахує лише ok", () => {
  const envs = [
    envelope({ status: "ok" }),
    envelope({ collected_at: "2026-09-30T13:44:59Z", interval_s: 300, status: "ok" }), // stale
    envelope({ status: "error" }),
    envelope({ status: "not_measured" }),
    null, // missing
  ];
  assert.deepEqual(DashRender.sourcesSummary(envs, NOW), { ok: 1, total: 5 });
});

test("sourcesSummary: порожній перелік — {ok:0, total:0}", () => {
  assert.deepEqual(DashRender.sourcesSummary([], NOW), { ok: 0, total: 0 });
});

test("sourcesSummary: усі ok — ok === total", () => {
  const envs = [envelope({}), envelope({ section: "y" })];
  assert.deepEqual(DashRender.sourcesSummary(envs, NOW), { ok: 2, total: 2 });
});

// ─── renderSection: стани ніколи не зелені, крім ok ─────────────────────────

for (const [status, expectState] of [
  ["stale", "stale"],
  ["error", "error"],
  ["not_measured", "not_measured"],
]) {
  test(`renderSection: status ${status} — не st-good у бейджі`, () => {
    const html = DashRender.renderSection(envelope({ status }), NOW, { ord: 1 });
    assert.ok(!html.includes("st-good"), html);
    assert.ok(html.includes(DashRender.badgeHtml(expectState)), html);
  });
}

test("renderSection: env відсутній (missing) — не st-good, загальний вигляд «не підключено»", () => {
  const html = DashRender.renderSection(null, NOW, { key: "quotas", title: "Квоти ШІ", ord: 0 });
  assert.ok(!html.includes("st-good"));
  assert.ok(html.includes("не підключено"));
  assert.ok(html.includes("Квоти ШІ"));
});

test("renderSection: старий collected_at зі status ok у файлі — усе одно stale, не st-good", () => {
  const env = envelope({ collected_at: "2026-09-30T10:00:00Z", interval_s: 300, status: "ok" });
  const html = DashRender.renderSection(env, NOW, { ord: 5 });
  assert.ok(!html.includes("st-good"));
  assert.ok(html.includes("застаріли"));
});

test("renderSection: невідомий розділ без віджета — загальний вигляд «ключ — значення»", () => {
  const env = envelope({ section: "невідомий-розділ", data: { foo: "bar", n: 3 } });
  const html = DashRender.renderSection(env, NOW, {});
  assert.ok(html.includes("без віджета"));
  assert.ok(html.includes("foo"));
  assert.ok(html.includes("bar"));
});

test("renderSection: текст із <script> у data виводиться як текст, не як розмітка", () => {
  const env = envelope({
    section: "невідомий-розділ",
    title: "<img src=x onerror=alert(1)>",
    data: { payload: "<script>alert(1)</script>" },
  });
  const html = DashRender.renderSection(env, NOW, {});
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(html.includes("&lt;img"));
});

test("renderSection: t5-віджет рендерить кроки без HTML-ін'єкції з назви кроку", () => {
  const env = envelope({
    section: "t5",
    title: "Трек T5",
    data: {
      steps: [
        { n: 1, name: "<b>Хвости</b>", state: "good", label: "закрито" },
        {
          n: 6,
          name: "Автономія під наглядом",
          state: "none",
          label: "лише рішенням",
          locked: true,
        },
      ],
    },
  });
  const html = DashRender.renderSection(env, NOW, { ord: 5 });
  assert.ok(html.includes('<ol class="steps">'));
  assert.ok(!html.includes("<b>Хвости</b>"));
  assert.ok(html.includes("&lt;b&gt;Хвости&lt;/b&gt;"));
  assert.ok(html.includes("locked"));
});

test("renderSection: trend-віджет рендерить стовпчики тижнів і легенду", () => {
  const env = envelope({
    section: "trend",
    title: "Продукт і процес",
    data: {
      weeks: [
        { week: "06.07", product: 6, process: 7 },
        { week: "28.09", product: 0, process: 7 },
      ],
      note: "Останній продуктовий коміт — приклад.",
    },
  });
  const html = DashRender.renderSection(env, NOW, { ord: 6 });
  assert.ok(html.includes("chart-bars"));
  assert.ok(html.includes("продукт: apps/"));
  assert.ok(html.includes("06.07"));
  assert.ok(html.includes("Останній продуктовий коміт"));
});

test("renderSection: приклад — тег «приклад» у шапці розділу", () => {
  const html = DashRender.renderSection(envelope({}), NOW, { ord: 1, example: true });
  assert.ok(html.includes("приклад"));
});

// ─── Правки оркестратора за рецензією Gemini 3.8 Flash (#203), не агента A8 ───

test("pageNow: справжній знімок — годинник глядача, не час знімка (знімок міг лежати)", () => {
  const clock = Date.parse("2026-09-30T16:00:00Z");
  assert.equal(DashRender.pageNow("2026-09-30T14:00:00Z", false, clock), clock);
});

test("pageNow: ?example — час фікстури; кривий час — годинник", () => {
  const clock = Date.parse("2026-10-06T09:00:00Z");
  assert.equal(DashRender.pageNow("2026-09-30T14:00:00Z", true, clock), Date.parse(NOW));
  assert.equal(DashRender.pageNow("не час", true, clock), clock);
});

test("знімок, що пролежав 2 год: розділ з interval 300 — stale на сторінці", () => {
  const env = envelope({ collected_at: "2026-09-30T14:00:00Z", interval_s: 300 });
  const now = DashRender.pageNow("2026-09-30T14:00:00Z", false, Date.parse("2026-09-30T16:00:00Z"));
  assert.equal(DashRender.sectionState(env, now), "stale");
  assert.equal(DashRender.sourcesSummary([env], now).ok, 0);
});

test("t5-віджет: розділ не ok — жодного st-good і в кроках", () => {
  for (const status of ["stale", "error", "not_measured"]) {
    const env = envelope({
      section: "t5",
      status,
      data: { steps: [{ n: 1, name: "Хвости", state: "good", label: "закрито" }] },
    });
    const html = DashRender.renderSection(env, NOW, { ord: 5 });
    assert.ok(!html.includes("st-good"), status + ": " + html);
    assert.ok(html.includes("закрито"));
  }
});

test("t5-віджет: розділ ok — закритий крок зелений", () => {
  const env = envelope({
    section: "t5",
    data: { steps: [{ n: 1, name: "Хвости", state: "good", label: "закрито" }] },
  });
  const html = DashRender.renderSection(env, NOW, { ord: 5 });
  assert.ok(html.includes('<span class="st st-good"><i>✓</i>закрито</span>'), html);
});

test("sectionState: невідомий status («green») зі свіжим часом — не ok", () => {
  assert.notEqual(DashRender.sectionState(envelope({ status: "green" }), NOW), "ok");
});

test("trend-віджет: висота стовпчика — частка від максимуму тижня", () => {
  const env = envelope({
    section: "trend",
    data: { weeks: [{ week: "w1", product: 5, process: 10 }] },
  });
  const html = DashRender.renderSection(env, NOW, {});
  assert.ok(html.includes('class="b-prod" style="height:50%"'), html);
  assert.ok(html.includes('class="b-proc" style="height:100%"'), html);
});

// Контракт зі збирачами (#163, PR #204): поля, які справді друкують dash-t5.sh і
// dash-trend.sh. Правка оркестратора за рецензією Gemini 3.8 Flash (#204).
test("t5-віджет: формат dash-t5.sh {n, title, closed} — назви й бейджі є", () => {
  const env = envelope({
    section: "t5",
    data: {
      steps: [
        { n: 1, title: "Хвости", closed: true },
        { n: 2, title: "Сервер A8", closed: false },
      ],
      first_open: 2,
    },
  });
  const html = DashRender.renderSection(env, NOW, { ord: 5 });
  assert.ok(html.includes("Хвости") && html.includes("Сервер A8"), html);
  assert.ok(html.includes('<span class="st st-good"><i>✓</i>закрито</span>'), html);
  assert.ok(html.includes('<span class="st st-none"><i>–</i>відкрито</span>'), html);
});

test("trend-віджет: формат dash-trend.sh {week_start, product, process} — підпис дд.мм, не undefined", () => {
  const env = envelope({
    section: "trend",
    data: { weeks: [{ week_start: "2026-09-28T00:00:00Z", product: 1, process: 22 }] },
  });
  const html = DashRender.renderSection(env, NOW, {});
  assert.ok(!html.includes("undefined"), html);
  assert.ok(html.includes('<div class="wk">28.09</div>'), html);
});
