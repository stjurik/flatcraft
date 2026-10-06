/* global module, window */
"use strict";

// render.js — чисті функції показу пульту (ADR-042 §10): без DOM, без побічних
// ефектів, щоб той самий код ганявся і в браузері (file://, тож без ES-модулів —
// звідси й подвійний експорт нижче), і під `node --test` без браузера (CI job
// «Guard-скрипти», контейнер оракула на A8 — жодного з них Playwright не має).
//
// ЧЕСНІСТЬ ДАНИХ (ADR-042 §3) — головний інваріант: sectionState ніколи не
// повертає «ok» для розділу, старшого за 3 × interval_s, навіть якщо сам файл
// каже status: "ok" (знімок міг пролежати годину, перш ніж сторінку відкрили).
// sourcesSummary і renderSection рахують стан саме через sectionState, а не
// читають env.status напряму, — так усі три лишаються узгодженими одним
// визначенням, а не трьома, що можуть розійтись.
(function () {
  var STALE_FACTOR = 3;

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (c) {
      if (c === "&") return "&amp;";
      if (c === "<") return "&lt;";
      if (c === ">") return "&gt;";
      if (c === '"') return "&quot;";
      return "&#39;";
    });
  }

  function toMs(t) {
    if (typeof t === "number") return t;
    var ms = Date.parse(t);
    return isNaN(ms) ? NaN : ms;
  }

  // Та сама межа, що dash-schema.sh stale: вік > 3×interval_s — застаріле;
  // час у майбутньому більш ніж на interval_s — несправний годинник, теж не ok.
  function isStaleByAge(env, now) {
    var nowMs = toMs(now);
    var collMs = toMs(env.collected_at);
    var intervalMs = Number(env.interval_s) * 1000;
    if (!isFinite(nowMs) || !isFinite(collMs) || !isFinite(intervalMs) || intervalMs <= 0) {
      return true;
    }
    var age = nowMs - collMs;
    if (age > STALE_FACTOR * intervalMs) return true;
    if (-age > intervalMs) return true;
    return false;
  }

  // sectionState(env, now) → ok | stale | error | not_measured | missing.
  function sectionState(env, now) {
    if (!env) return "missing";
    if (env.status === "error") return "error";
    if (env.status === "not_measured") return "not_measured";
    if (env.status === "stale") return "stale";
    if (isStaleByAge(env, now)) return "stale";
    return env.status === "ok" ? "ok" : "error";
  }

  // sourcesSummary(envs, now) → {ok, total}. total — усі передані розділи
  // (підключені чи ні), ok — лише ті, чий sectionState саме "ok".
  function sourcesSummary(envs, now) {
    var list = envs || [];
    var ok = 0;
    for (var i = 0; i < list.length; i++) {
      if (sectionState(list[i], now) === "ok") ok++;
    }
    return { ok: ok, total: list.length };
  }

  var STATE_BADGE = {
    ok: { cls: "st-good", glyph: "✓", label: "дані свіжі" },
    stale: { cls: "st-warn", glyph: "◷", label: "застаріли" },
    error: { cls: "st-crit", glyph: "✕", label: "збирач не відповів" },
    not_measured: { cls: "st-none", glyph: "–", label: "не виміряно" },
    missing: { cls: "st-none", glyph: "–", label: "не підключено" },
  };

  function badgeHtml(state) {
    var b = STATE_BADGE[state] || STATE_BADGE.error;
    return '<span class="st ' + b.cls + '"><i>' + b.glyph + "</i>" + esc(b.label) + "</span>";
  }

  function agoText(env, now) {
    if (!env) return "немає даних";
    var nowMs = toMs(now);
    var collMs = toMs(env.collected_at);
    if (!isFinite(nowMs) || !isFinite(collMs)) return "невідомо коли";
    var mins = Math.round((nowMs - collMs) / 60000);
    if (mins <= 0) return "щойно";
    if (mins < 60) return mins + " хв тому";
    var hours = Math.floor(mins / 60);
    if (hours < 48) return hours + " год тому";
    return Math.floor(hours / 24) + " дн тому";
  }

  function rowsHtml(pairs) {
    return (
      '<div class="rows">' +
      pairs
        .map(function (p) {
          return (
            '<div class="row"><div class="k">' +
            esc(p[0]) +
            '</div><div class="v">' +
            p[1] +
            "</div></div>"
          );
        })
        .join("") +
      "</div>"
    );
  }

  // Розділ без власного віджета — «ключ — значення» з позначкою «без віджета»
  // (ADR-042 §1): новий збирач видно на пульті одразу, свій вигляд — пізніше.
  function genericBody(env) {
    var data = (env && env.data) || {};
    var keys = Object.keys(data);
    var tag = '<span class="tag">без віджета</span>';
    if (keys.length === 0) {
      return tag + '<p class="muted">Розділ не має даних для показу.</p>';
    }
    var pairs = keys.map(function (k) {
      var v = data[k];
      var text = v !== null && typeof v === "object" ? JSON.stringify(v) : String(v);
      return [k, '<span class="mono">' + esc(text) + "</span>"];
    });
    return tag + rowsHtml(pairs);
  }

  function missingBody(title) {
    return (
      '<p class="muted">Розділ «' +
      esc(title) +
      "» ще не підключено — збирач з’явиться в наступній хвилі (ADR-042 §10).</p>"
    );
  }

  var STEP_BADGE = {
    good: { cls: "st-good", glyph: "✓" },
    warn: { cls: "st-warn", glyph: "◐" },
    serious: { cls: "st-serious", glyph: "!" },
    none: { cls: "st-none", glyph: "–" },
  };

  // Віджет «Трек T5» (хвиля 1) — крок за кроком, як у макеті v3.
  // state — стан розділу: якщо він не ok, «зелений» крок показується сірим
  // (ADR-042 §3 п.2 — розділ не ok ніколи не зелений, і всередині теж;
  // правка оркестратора за рецензією Gemini 3.8 Flash, #203).
  function widgetT5(env, now, state) {
    var steps = (env.data && env.data.steps) || [];
    var items = steps
      .map(function (s) {
        // Збирач dash-t5.sh (#163, PR #204) друкує {n, title, closed}; макет — {name,
        // state, label}. Приймаємо обидва (правка оркестратора за рецензією Flash #204:
        // без цього назви кроків порожні, а бейджів немає).
        var closed = s.closed === true ? true : s.closed === false ? false : null;
        var stepState = s.state || (closed === true ? "good" : closed === false ? "none" : "");
        var stepLabel =
          s.label || (closed === true ? "закрито" : closed === false ? "відкрито" : "");
        var stepName = s.name || s.title || "";
        var b = STEP_BADGE[stepState] || STEP_BADGE.none;
        if (state !== "ok" && b === STEP_BADGE.good) b = STEP_BADGE.none;
        var badge = stepLabel
          ? ' <span class="st ' + b.cls + '"><i>' + b.glyph + "</i>" + esc(stepLabel) + "</span>"
          : "";
        var note = s.note ? '<div class="cr">' + esc(s.note) + "</div>" : "";
        return (
          "<li" +
          (s.locked ? ' class="locked"' : "") +
          '><span class="no">' +
          esc(String(s.n != null ? s.n : "")) +
          '</span><div><div class="nm">' +
          esc(stepName) +
          badge +
          "</div>" +
          note +
          "</div></li>"
        );
      })
      .join("");
    return '<ol class="steps">' + items + "</ol>";
  }

  // Віджет «Продукт і процес» (хвиля 1) — графік тижнів, стовпчики без SVG
  // (висота — відсоток від максимуму тижня), так само читається на 400 px.
  // Підпис тижня: макет дає week «06.07», збирач dash-trend.sh (#163, PR #204) —
  // week_start ISO; без цього під стовпчиками стояло «undefined» (рецензія Flash #204).
  function weekLabel(w) {
    if (w.week != null) return String(w.week);
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(w.week_start || ""));
    return m ? m[3] + "." + m[2] : "?";
  }

  function widgetTrend(env) {
    var data = env.data || {};
    var weeks = data.weeks || [];
    var max = 1;
    weeks.forEach(function (w) {
      max = Math.max(max, Number(w.product) || 0, Number(w.process) || 0);
    });
    var cols = weeks
      .map(function (w) {
        var prod = Number(w.product) || 0;
        var proc = Number(w.process) || 0;
        var prodH = Math.round((prod / max) * 100);
        var procH = Math.round((proc / max) * 100);
        var label = esc(weekLabel(w)) + ": продукт " + prod + ", процес " + proc;
        return (
          '<div class="col" title="' +
          label +
          '"><div class="bars"><span class="b-prod" style="height:' +
          prodH +
          '%"></span><span class="b-proc" style="height:' +
          procH +
          '%"></span></div><div class="wk">' +
          esc(weekLabel(w)) +
          "</div></div>"
        );
      })
      .join("");
    var legend =
      '<div class="legend"><span><i style="background:var(--s1)"></i>продукт: apps/, workers/, packages/</span>' +
      '<span><i style="background:var(--s2)"></i>процес: усе інше</span></div>';
    var note = data.note ? '<div class="callout">' + esc(data.note) + "</div>" : "";
    return legend + '<div class="chart-bars">' + cols + "</div>" + note;
  }

  var WIDGETS = {
    t5: widgetT5,
    trend: widgetTrend,
  };

  // renderSection(env, now, opts?) → HTML-рядок однієї панелі розділу.
  // opts: {key, title, ord, example} — потрібні, коли env відсутній (розділ ще
  // не підключено) або коли викликає сторінка, що знає порядковий номер і режим
  // показу приклада; саме env.section/env.title — дефолт, коли env є.
  function renderSection(env, now, opts) {
    opts = opts || {};
    var key = opts.key || (env && env.section) || "";
    var title = opts.title || (env && env.title) || key;
    var state = sectionState(env, now);
    var source = env && env.source;
    var exampleTag = opts.example ? ' <span class="tag tag-real">приклад</span>' : "";
    var meta =
      (source ? esc(source) + " · " : "") + "зібрано " + esc(agoText(env, now)) + exampleTag;
    var body;
    if (!env) {
      body = missingBody(title);
    } else if (WIDGETS[key]) {
      body = WIDGETS[key](env, now, state);
    } else {
      body = genericBody(env);
    }
    var ordHtml = opts.ord != null ? '<span class="ord">' + esc(String(opts.ord)) + "</span>" : "";
    return (
      '<section class="panel' +
      (state === "error" ? " is-error" : "") +
      '" id="sec-' +
      esc(key) +
      '"><div class="panel-h"><div><h2>' +
      ordHtml +
      esc(title) +
      '</h2><div class="meta">' +
      meta +
      "</div></div>" +
      badgeHtml(state) +
      '</div><div class="panel-b">' +
      body +
      "</div></section>"
    );
  }

  // pageNow(snapCollectedAt, example, clockMs) → «зараз» для сторінки, мс.
  // Справжній знімок судиться за годинником того, хто дивиться: знімок міг
  // лежати годину (ADR-042 §3 п.1). Лише ?example бере час самої фікстури, щоб
  // приклад виглядав так, як задумано, у будь-який день. Правка оркестратора за
  // рецензією Gemini 3.8 Flash (#203): раніше «зараз» завжди був часом знімка.
  function pageNow(snapCollectedAt, example, clockMs) {
    if (example) {
      var snapMs = toMs(snapCollectedAt);
      if (isFinite(snapMs)) return snapMs;
    }
    return clockMs;
  }

  var DashRender = {
    pageNow: pageNow,
    sectionState: sectionState,
    sourcesSummary: sourcesSummary,
    renderSection: renderSection,
    badgeHtml: badgeHtml,
    agoText: agoText,
    esc: esc,
    WIDGETS: WIDGETS,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = DashRender;
  }
  if (typeof window !== "undefined") {
    window.DashRender = DashRender;
  }
})();
