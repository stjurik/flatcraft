/**
 * Склад форми студії — СПРАВЖНІЙ AutoForm, кожен шаблон реєстру (issue #96).
 *
 * Решта web unit-тестів бачить AutoForm-стаб, який рендерить `null`
 * (src/test/flatcraft-ui-stub.tsx), тож жоден із них не бачив, які поля
 * потрапляють у форму. Саме так регресія Registry-міграції (PR #92) пройшла
 * непоміченою: `def.ui.visibleFields` ніхто не читав, і в режимі деталі форма
 * показувала `bend_direction` і заглушки масивів, які старі per-slug редактори
 * свідомо ховали (`.omit()`, Hotfix 2.10.e).
 *
 * Тест іде по `TEMPLATE_REGISTRY`, а не по списку slug'ів: новий шаблон
 * (wall_shelf, enclosed_shelf) потрапляє сюди сам, без правки тесту.
 */
import { TEMPLATE_REGISTRY, type TemplateDefinition } from "@flatcraft/templates";
import type * as FlatcraftUi from "@flatcraft/ui";
import { renderToString } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { z } from "zod";

import { RegistryTemplateEditor } from "./registry-template-editor";

// Справжні AutoForm/zodIssuesToFieldErrors замість стабу; решта (SegmentedControl
// тощо) лишається стабом. Аліас "@flatcraft/ui/parameter-form" → packages/ui/src
// — у vitest.config.ts.
vi.mock("@flatcraft/ui", async (importOriginal) => {
  const stub = await importOriginal<typeof FlatcraftUi>();
  const form = await vi.importActual<typeof FlatcraftUi>("@flatcraft/ui/parameter-form");
  return {
    ...stub,
    AutoForm: form.AutoForm,
    zodIssuesToFieldErrors: form.zodIssuesToFieldErrors,
  };
});

type AnyDefinition = TemplateDefinition<Record<string, unknown>>;

// Реєстр різнотипний (див. коментар у registry.ts) — для генеричного обходу
// зводимо записи до спільного типу; кожне визначення типізоване у своєму файлі.
const DEFINITIONS = Object.values(TEMPLATE_REGISTRY) as unknown as readonly AnyDefinition[];

// Кожне поле AutoForm має рівно один із цих testid: `field-` (number/enum),
// `literal-`, `auto-form-unsupported-` (заглушка для масивів тощо).
// `field-error-<name>` сюди не потрапляє: після `field-` іде `error-…` з дефісом.
const FIELD_TESTID = /data-testid="(?:field|literal|auto-form-unsupported)-([A-Za-z0-9_]+)"/g;

// Поля, якими в студії задається напрям гибу. Hotfix 2.10.e: у формі деталі їх
// немає — напрям завжди дефолтний і видно його лише на кресленні (PDF).
const BEND_DIRECTION_FIELDS = ["bend_direction", "bends"];

function render(def: AnyDefinition, visibleFields?: readonly string[]): string {
  return renderToString(
    <RegistryTemplateEditor
      def={def}
      value={def.defaults}
      onChange={() => {}}
      thicknessMm={2}
      {...(visibleFields ? { visibleFields } : {})}
    />,
  );
}

function renderedFields(html: string): string[] {
  return [...html.matchAll(FIELD_TESTID)].map((m) => m[1] ?? "").sort();
}

function schemaFields(def: AnyDefinition): string[] {
  // ADR-033 §2 ALT-C: схема може бути refined (ZodEffects) — поля беремо з
  // базового ZodObject.
  let schema: z.ZodTypeAny = def.schema;
  while (schema instanceof z.ZodEffects) schema = schema.innerType();
  return Object.keys((schema as z.ZodObject<z.ZodRawShape>).shape);
}

// Поля, якими керує SegmentedControl над формою, — не поля AutoForm.
function formFields(def: AnyDefinition): string[] {
  const segmented = new Set(
    (def.ui.extraControls ?? []).flatMap((c) => (c.kind === "segmented" ? [c.field] : [])),
  );
  return schemaFields(def).filter((f) => !segmented.has(f));
}

describe("Склад форми студії — справжній AutoForm, усі шаблони реєстру (issue #96)", () => {
  it("тест не порожній: хоч один шаблон реєстру ховає поля через ui.visibleFields", () => {
    const hiding = DEFINITIONS.filter(
      (def) => def.ui.visibleFields && def.ui.visibleFields.length < formFields(def).length,
    );
    expect(hiding.length).toBeGreaterThan(0);
  });

  describe.each(DEFINITIONS.map((def) => [def.slug, def] as const))("%s", (_slug, def) => {
    it("режим деталі: у формі рівно def.ui.visibleFields (без них — усі поля схеми)", () => {
      const expected = def.ui.visibleFields ?? formFields(def);
      expect(renderedFields(render(def))).toEqual([...expected].sort());
    });

    it("режим деталі: без заглушок і без поля напряму гибу", () => {
      const html = render(def);
      expect(html).not.toContain('data-testid="auto-form-unsupported-');
      for (const field of BEND_DIRECTION_FIELDS) {
        expect(renderedFields(html)).not.toContain(field);
      }
    });

    it("режим продукту без змін: у формі рівно allowlist продукту, навіть поля, які шаблон ховає", () => {
      // Allowlist з усіх полів форми, включно з тими, що шаблон ховає у режимі
      // деталі: продукт має пріоритет над def.ui.visibleFields, як і до фіксу.
      const allowlist = formFields(def);
      expect(renderedFields(render(def, allowlist))).toEqual([...allowlist].sort());
    });

    for (const product of def.products ?? []) {
      it(`продукт ${product.slug}: у формі рівно userEditableFields`, () => {
        expect(renderedFields(render(def, product.userEditableFields))).toEqual(
          [...product.userEditableFields].sort(),
        );
      });
    }
  });
});
