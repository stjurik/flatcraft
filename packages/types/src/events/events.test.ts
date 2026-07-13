import { describe, expect, it } from "vitest";

import {
  assertNoPii,
  DEFAULT_PROCESS,
  EVENT_TYPES,
  EventPayloadSchema,
  toEventRow,
  type EventPayload,
} from "./events.js";

describe("EventPayloadSchema — discriminated union", () => {
  it("парсить export_requested з params та проставляє process за замовчуванням", () => {
    const parsed = EventPayloadSchema.parse({
      event_type: "export_requested",
      template_slug: "l_bracket",
      session_hash: "abc",
      params: { legA_mm: 60 },
    });
    expect(parsed.event_type).toBe("export_requested");
    expect(parsed.process).toBe(DEFAULT_PROCESS);
  });

  it("validation_rejected вимагає error_code", () => {
    const bad = EventPayloadSchema.safeParse({
      event_type: "validation_rejected",
      template_slug: "z_bracket",
      session_hash: null,
      params: { bend_radius_mm: 2.5 },
      // error_code відсутній
    });
    expect(bad.success).toBe(false);
  });

  it("cad_completed вимагає невід'ємний ціл. duration_ms", () => {
    expect(
      EventPayloadSchema.safeParse({
        event_type: "cad_completed",
        template_slug: "l_bracket",
        session_hash: null,
        duration_ms: -5,
      }).success,
    ).toBe(false);
    expect(
      EventPayloadSchema.safeParse({
        event_type: "cad_completed",
        template_slug: "l_bracket",
        session_hash: null,
        duration_ms: 1200,
      }).success,
    ).toBe(true);
  });

  it("web_vital обмежує metric відомим набором", () => {
    expect(
      EventPayloadSchema.safeParse({
        event_type: "web_vital",
        template_slug: null,
        session_hash: "s",
        params: { metric: "LCP", value_ms: 10 },
      }).success,
    ).toBe(false);
  });

  it("покриває рівно 8 типів подій (додано feedback_submitted у Phase 3.4)", () => {
    expect(EVENT_TYPES).toHaveLength(8);
  });
});

describe("assertNoPii", () => {
  it("пропускає чисту геометрію", () => {
    expect(() => assertNoPii({ legA_mm: 60, holes: [{ diameter_mm: 8 }] })).not.toThrow();
  });

  it("кидає на email (верхній рівень)", () => {
    expect(() => assertNoPii({ email: "a@b.c" })).toThrow(/PII/);
  });

  it("кидає на вкладений ip", () => {
    expect(() => assertNoPii({ meta: { nested: { ip: "1.2.3.4" } } })).toThrow(/PII/);
  });

  it("ловить PII у масиві та незалежно від регістру", () => {
    expect(() => assertNoPii({ list: [{ Email: "x@y.z" }] })).toThrow(/PII/);
  });
});

describe("toEventRow", () => {
  it("проєктує cad_completed у рядок з duration_ms і null-полями", () => {
    const payload: EventPayload = {
      event_type: "cad_completed",
      template_slug: "l_bracket",
      process: DEFAULT_PROCESS,
      session_hash: "h",
      duration_ms: 900,
    };
    const row = toEventRow(payload);
    expect(row).toMatchObject({
      event_type: "cad_completed",
      template_slug: "l_bracket",
      duration_ms: 900,
      params: null,
      error_code: null,
      session_hash: "h",
    });
  });

  it("проєктує validation_rejected з params + error_code", () => {
    const row = toEventRow({
      event_type: "validation_rejected",
      template_slug: "z_bracket",
      process: DEFAULT_PROCESS,
      session_hash: null,
      params: { bend_radius_mm: 2.5 },
      error_code: "RADIUS_NOT_ALLOWED",
    });
    expect(row.error_code).toBe("RADIUS_NOT_ALLOWED");
    expect(row.params).toEqual({ bend_radius_mm: 2.5 });
    expect(row.duration_ms).toBeNull();
  });

  it("кидає, якщо params містить PII (writer-guard)", () => {
    expect(() =>
      toEventRow({
        event_type: "export_requested",
        template_slug: "l_bracket",
        process: DEFAULT_PROCESS,
        session_hash: null,
        params: { legA_mm: 60, email: "leak@x.y" },
      }),
    ).toThrow(/PII/);
  });
});
