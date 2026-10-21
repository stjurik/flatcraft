/**
 * Hotfix 2.9.c (ADR-022): export-gate валідатор має працювати у браузері —
 * без `node:fs`, лише на `bakedSpec`. Browser-safety (відсутність node:* у
 * графі) перевіряється статичним скануванням у `generated/baked-spec.test.ts`;
 * тут — функціональна перевірка, що клієнт ловить ті самі помилки, що й сервер.
 */
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  L_BRACKET_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  Z_BRACKET_DEFAULT_PARAMETERS,
  type ExportRequest,
} from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import { bakedSpec } from "../generated/baked-spec.js";
import {
  sheetDimensionsFor,
  validateExportBends,
  validateExportHoles,
  validateExportSheet,
} from "./export-gate.js";

function lBracket(overrides: {
  thickness_mm: number;
  material_code?: string;
  bend_radius_mm?: 1 | 2.5 | 4 | 5;
}): ExportRequest {
  return {
    template_slug: "l_bracket",
    parameters: {
      ...L_BRACKET_DEFAULT_PARAMETERS,
      ...(overrides.bend_radius_mm !== undefined
        ? { bend_radius_mm: overrides.bend_radius_mm }
        : {}),
    },
    material_code: overrides.material_code ?? "cold_rolled_steel",
    thickness_mm: overrides.thickness_mm,
  };
}

describe("validateExportBends (browser, bakedSpec)", () => {
  it("t=5 / R=2.5 cold_rolled_steel → RADIUS_NOT_ALLOWED, allowed [4, 5]", () => {
    const issues = validateExportBends(
      lBracket({ thickness_mm: 5, bend_radius_mm: 2.5 }),
      bakedSpec,
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("RADIUS_NOT_ALLOWED");
    expect(issues[0]?.field).toBe("bend_radius_mm");
    expect(issues[0]?.allowed).toEqual([4, 5]);
    expect(issues[0]?.thickness).toBe(5);
    expect(issues[0]?.message).toMatch(/Збільшіть радіус/);
  });

  it("t=5 / R=4 cold_rolled_steel → валідно (порожній список)", () => {
    const issues = validateExportBends(lBracket({ thickness_mm: 5, bend_radius_mm: 4 }), bakedSpec);
    expect(issues).toEqual([]);
  });

  it("невідома товщина → THICKNESS_NOT_SUPPORTED", () => {
    const issues = validateExportBends(lBracket({ thickness_mm: 7 }), bakedSpec);
    expect(issues[0]?.code).toBe("THICKNESS_NOT_SUPPORTED");
  });
});

type LBracketHoleOverride = {
  leg: "A" | "B";
  distance_from_edge_mm: number;
  distance_from_bend_mm: number;
  diameter_mm: number;
};

function lBracketWithHoles(
  thickness_mm: number,
  bend_radius_mm: 1 | 2.5 | 4 | 5,
  holes: LBracketHoleOverride[],
  material_code = "cold_rolled_steel",
): ExportRequest {
  return {
    template_slug: "l_bracket",
    parameters: { ...L_BRACKET_DEFAULT_PARAMETERS, bend_radius_mm, holes },
    material_code,
    thickness_mm,
  };
}

type ZBracketHoleOverride = {
  segment: "T" | "M" | "B";
  distance_from_edge_mm: number;
  distance_from_bend_mm: number;
  diameter_mm: number;
};

function zBracketWithHoles(
  thickness_mm: number,
  bend_radius_mm: 1 | 2.5 | 4 | 5,
  holes: ZBracketHoleOverride[],
  material_code = "cold_rolled_steel",
): ExportRequest {
  return {
    template_slug: "z_bracket",
    parameters: { ...Z_BRACKET_DEFAULT_PARAMETERS, bend_radius_mm, holes },
    material_code,
    thickness_mm,
  };
}

describe("validateExportHoles (browser, bakedSpec) — рішення yurii 2026-10-11, правило від краю", () => {
  // cold_rolled_steel a=2.0, t=2, R=2.5 → мінімум від краю = 6.5 мм.
  it("l_bracket: край рівно a·t+R (D=9.5, Ø6) — допустимо", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 9.5, diameter_mm: 6 },
    ]);
    expect(validateExportHoles(req, bakedSpec)).toEqual([]);
  });

  it("l_bracket: a·t+R − 0.1 (D=9.4, Ø6) — HOLE_TOO_CLOSE_TO_BEND", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 9.4, diameter_mm: 6 },
    ]);
    const issues = validateExportHoles(req, bakedSpec);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("HOLE_TOO_CLOSE_TO_BEND");
    expect(issues[0]?.field).toBe("holes[0].distance_from_bend_mm");
  });

  it("l_bracket: той самий D=9.5, але Ø8 — більший діаметр зсуває край ближче до гиба → помилка", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 9.5, diameter_mm: 8 },
    ]);
    const issues = validateExportHoles(req, bakedSpec);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("HOLE_TOO_CLOSE_TO_BEND");
  });

  it("l_bracket: головний регресійний кейс — D=6.5 (за старим правилом «від центру» пройшло б) → помилка", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 6.5, diameter_mm: 6 },
    ]);
    const issues = validateExportHoles(req, bakedSpec);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.message).toMatch(/Відсуньте отвір/);
    expect(issues[0]?.message).toMatch(/6\.5/);
    expect(issues[0]?.message).toMatch(/9\.5/);
  });

  it("l_bracket: D=9.7 Ø6.4 — край 6.499999999999999 (IEEE-754) з допуском 1e-9 — допустимо", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 9.7, diameter_mm: 6.4 },
    ]);
    expect(validateExportHoles(req, bakedSpec)).toEqual([]);
  });

  it("l_bracket: D=9.69 Ø6.4 — дійсно ближче за межу, допуск не маскує → HOLE_TOO_CLOSE_TO_BEND", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 9.69, diameter_mm: 6.4 },
    ]);
    const issues = validateExportHoles(req, bakedSpec);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("HOLE_TOO_CLOSE_TO_BEND");
  });

  it("l_bracket: D=30 — контроль далеко від межі → допустимо", () => {
    const req = lBracketWithHoles(2, 2.5, [
      { leg: "A", distance_from_edge_mm: 20, distance_from_bend_mm: 30, diameter_mm: 6 },
    ]);
    expect(validateExportHoles(req, bakedSpec)).toEqual([]);
  });

  it("z_bracket: той самий t/R, D=6.5 (segment T) → HOLE_TOO_CLOSE_TO_BEND", () => {
    const req = zBracketWithHoles(2, 2.5, [
      { segment: "T", distance_from_edge_mm: 20, distance_from_bend_mm: 6.5, diameter_mm: 6 },
    ]);
    expect(validateExportHoles(req, bakedSpec)).toHaveLength(1);
  });

  it("z_bracket: D=12 — контроль далеко від межі → допустимо", () => {
    const req = zBracketWithHoles(2, 2.5, [
      { segment: "T", distance_from_edge_mm: 20, distance_from_bend_mm: 12, diameter_mm: 6 },
    ]);
    expect(validateExportHoles(req, bakedSpec)).toEqual([]);
  });

  it("enclosed_shelf — немає поля distance_from_bend_mm → []", () => {
    const req: ExportRequest = {
      template_slug: "enclosed_shelf",
      parameters: ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      material_code: "cold_rolled_steel",
      thickness_mm: 2,
    };
    expect(validateExportHoles(req, bakedSpec)).toEqual([]);
  });
});

describe("validateExportSheet (browser, bakedSpec) — CLAUDE.md §7 п.4", () => {
  it("enclosed_shelf t=8 R=5 900×300 (3 гиби, без ребра) → SHEET_EXCEEDS_MAX_LENGTH", () => {
    // flat_bottom + 2·BA + 2·(depth-tr) ≈ 1472мм > max_bend_length_mm=1000 для t=8.
    const req: ExportRequest = {
      template_slug: "enclosed_shelf",
      parameters: {
        ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
        width_mm: 900,
        depth_mm: 300,
        bend_radius_mm: 5,
      },
      material_code: "cold_rolled_steel",
      thickness_mm: 8,
    };
    const issues = validateExportSheet(req, bakedSpec);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("SHEET_EXCEEDS_MAX_LENGTH");
    expect(issues[0]?.message).toMatch(/Зменшіть/);
  });

  it("z_bracket cold_rolled_steel t=8 R=5 top=bottom=400 offset=214 width=100 → валідно (K матеріалу 0.34 менший за старий фіксований 0.4: 999.25мм < 1000, ADR-043/#246)", () => {
    const req: ExportRequest = {
      template_slug: "z_bracket",
      parameters: {
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        top_flange_mm: 400,
        bottom_flange_mm: 400,
        offset_mm: 214,
        bend_radius_mm: 5,
        width_mm: 100,
      },
      material_code: "cold_rolled_steel",
      thickness_mm: 8,
    };
    expect(validateExportSheet(req, bakedSpec)).toEqual([]);
  });

  it("той самий z_bracket кейс — K за матеріалом (ADR-043/#246): cold_rolled (999.25мм) і aluminum_5754 (997.76мм) валідні, stainless_304 (1000.32мм) перевищує", () => {
    const baseParams: typeof Z_BRACKET_DEFAULT_PARAMETERS = {
      ...Z_BRACKET_DEFAULT_PARAMETERS,
      top_flange_mm: 400,
      bottom_flange_mm: 400,
      offset_mm: 214,
      bend_radius_mm: 5,
      width_mm: 100,
    };
    for (const material_code of ["cold_rolled_steel", "aluminum_5754"]) {
      const req: ExportRequest = {
        template_slug: "z_bracket",
        parameters: baseParams,
        material_code,
        thickness_mm: 8,
      };
      expect(validateExportSheet(req, bakedSpec)).toEqual([]);
    }
    const req: ExportRequest = {
      template_slug: "z_bracket",
      parameters: baseParams,
      material_code: "stainless_304",
      thickness_mm: 8,
    };
    expect(validateExportSheet(req, bakedSpec).map((i) => i.code)).toEqual([
      "SHEET_EXCEEDS_MAX_LENGTH",
    ]);
  });

  it("enclosed_shelf t=2 на дефолтах (width=600, depth=200) → валідно, далеко від межі", () => {
    const req: ExportRequest = {
      template_slug: "enclosed_shelf",
      parameters: ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      material_code: "cold_rolled_steel",
      thickness_mm: 2,
    };
    expect(validateExportSheet(req, bakedSpec)).toEqual([]);
  });

  it("l_bracket маленький кронштейн → валідно", () => {
    expect(
      validateExportSheet(lBracket({ thickness_mm: 2, bend_radius_mm: 2.5 }), bakedSpec),
    ).toEqual([]);
  });

  describe("sheetDimensionsFor — enclosed_shelf bbox паритет з Python unfold.py", () => {
    // Числа отримані з `_sheet_dimensions_mm` (workers/cad), яка тепер рахує
    // bbox точно за формулами `unfold_enclosed_shelf` (left/right звисають
    // за bottom/back на (t+r)/2 навіть БЕЗ ребра — попередня формула рахувала
    // «низ» від 0 і занижувала висоту).
    it("без ребра (width=600 depth=200 t=2 R=2.5) — висота враховує left/right overhang", () => {
      const req: ExportRequest = {
        template_slug: "enclosed_shelf",
        parameters: ENCLOSED_SHELF_DEFAULT_PARAMETERS,
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBeCloseTo(992.3672557568464, 6);
      expect(dims!.heightMm).toBeCloseTo(398.4336278784232, 6);
    });

    it("з ребром height_mm=15 (width=600 depth=200 t=2 R=2.5)", () => {
      const req: ExportRequest = {
        template_slug: "enclosed_shelf",
        parameters: { ...ENCLOSED_SHELF_DEFAULT_PARAMETERS, stiffening_rib: { height_mm: 15 } },
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBeCloseTo(992.3672557568464, 6);
      expect(dims!.heightMm).toBeCloseTo(407.36725575684636, 6);
    });

    it("без ребра, великий (width=900 depth=300 t=8 R=5)", () => {
      const req: ExportRequest = {
        template_slug: "enclosed_shelf",
        parameters: {
          ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
          width_mm: 900,
          depth_mm: 300,
          bend_radius_mm: 5,
        },
        material_code: "cold_rolled_steel",
        thickness_mm: 8,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      // cold_rolled_steel: ratio=5/8=0.625 → multiplier 0.85 → K=0.40×0.85=0.34
      // (ADR-043/#246: K за матеріалом, не фіксований 0.4).
      expect(dims!.widthMm).toBeCloseTo(1472.2530952857132, 6);
      expect(dims!.heightMm).toBeCloseTo(592.6265476428566, 6);
    });
  });

  describe("sheetDimensionsFor — l_bracket/corner_angle/wall_shelf/perforated_panel bbox паритет з unfold.py", () => {
    // Усі числа нижче отримані локально: `uv run --directory workers/cad python`,
    // викликаючи `unfold_l_bracket`/`unfold_corner_angle`/`unfold_wall_shelf`/
    // `unfold_perforated_panel` (workers/cad/flatcraft_cad/unfold.py) з
    // t=2, R=2.5, матеріал cold_rolled_steel на default-параметрах шаблону
    // (override лише front_lip_mm для wall_shelf-кейсів). ratio=R/t=1.25 →
    // multiplier 1.0 → K=0.40 (ADR-043: той самий результат, що й старий
    // фіксований константний K=0.4, бо множник у цьому діапазоні — 1).
    // BA = (π/2)·(2.5+0.4·2) = 5.183627878423157мм — спільний доданок для
    // всіх, крім perforated_panel, де він входить у відступ двічі з кожного боку.

    it("l_bracket (legA=legB=60, width=100, t=2, R=2.5) — звірено з unfold_l_bracket: length_mm=116.18362787842315", () => {
      const req = lBracket({ thickness_mm: 2, bend_radius_mm: 2.5 });
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBe(100);
      expect(dims!.heightMm).toBeCloseTo(116.18362787842315, 9);
    });

    it("l_bracket той самий t=2, R=2.5 — aluminum_5754 (K=0.33) дає коротшу розгортку за cold_rolled_steel (K=0.40): Δ=π/2·0.07·2 (ADR-043/#246)", () => {
      const req = lBracket({
        thickness_mm: 2,
        bend_radius_mm: 2.5,
        material_code: "aluminum_5754",
      });
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBe(100);
      expect(dims!.heightMm).toBeCloseTo(115.96371639267187, 9);
      expect(116.18362787842315 - dims!.heightMm).toBeCloseTo((Math.PI / 2) * 0.07 * 2, 9);
    });

    it("corner_angle (legA=legB=50, width=80, t=2, R=2.5) — звірено з unfold_corner_angle: length_mm=96.18362787842315", () => {
      const req: ExportRequest = {
        template_slug: "corner_angle",
        parameters: { ...CORNER_ANGLE_DEFAULT_PARAMETERS, bend_radius_mm: 2.5 },
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBe(80);
      expect(dims!.heightMm).toBeCloseTo(96.18362787842315, 9);
    });

    it("wall_shelf з губою (back=80, shelf=150, lip=20, width=300, t=2, R=2.5) — звірено з unfold_wall_shelf: length_mm=242.3672557568463", () => {
      const req: ExportRequest = {
        template_slug: "wall_shelf",
        parameters: { ...WALL_SHELF_DEFAULT_PARAMETERS, bend_radius_mm: 2.5 },
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBe(300);
      expect(dims!.heightMm).toBeCloseTo(242.3672557568463, 9);
    });

    it("wall_shelf без губи (front_lip_mm=0, back=80, shelf=150, width=300, t=2, R=2.5) — звірено з unfold_wall_shelf: length_mm=226.18362787842315", () => {
      const req: ExportRequest = {
        template_slug: "wall_shelf",
        parameters: { ...WALL_SHELF_DEFAULT_PARAMETERS, bend_radius_mm: 2.5, front_lip_mm: 0 },
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBe(300);
      expect(dims!.heightMm).toBeCloseTo(226.18362787842315, 9);
    });

    it("perforated_panel (length=200, width=150, rib_height=30, t=2, R=2.5) — звірено з unfold_perforated_panel bbox: 261.3672557568463×211.3672557568463", () => {
      const req: ExportRequest = {
        template_slug: "perforated_panel",
        parameters: { ...PERFORATED_PANEL_DEFAULT_PARAMETERS, bend_radius_mm: 2.5 },
        material_code: "cold_rolled_steel",
        thickness_mm: 2,
      };
      const dims = sheetDimensionsFor(req, bakedSpec);
      expect(dims).not.toBeNull();
      expect(dims!.widthMm).toBeCloseTo(261.3672557568463, 9);
      expect(dims!.heightMm).toBeCloseTo(211.3672557568463, 9);
    });
  });
});

describe("validateExportSheet — невідома товщина не дублює THICKNESS_NOT_SUPPORTED", () => {
  it("t=7 (не підтримується) → рівно 1 помилка THICKNESS_NOT_SUPPORTED у validateExportBends, validateExportSheet мовчить", () => {
    const req: ExportRequest = {
      template_slug: "l_bracket",
      parameters: L_BRACKET_DEFAULT_PARAMETERS,
      material_code: "cold_rolled_steel",
      thickness_mm: 7,
    };
    expect(validateExportSheet(req, bakedSpec)).toEqual([]);
    const bendIssues = validateExportBends(req, bakedSpec);
    expect(bendIssues.filter((e) => e.code === "THICKNESS_NOT_SUPPORTED")).toHaveLength(1);
  });
});

describe("validateExportSheet — матеріал поза групою не дублює MATERIAL_NOT_ALLOWED (issue #257 п.3)", () => {
  it("z_bracket t=10 stainless_304 R=5 → рівно 1 MATERIAL_NOT_ALLOWED сумарно; validateExportSheet його не додає", () => {
    const req: ExportRequest = {
      template_slug: "z_bracket",
      parameters: { ...Z_BRACKET_DEFAULT_PARAMETERS, bend_radius_mm: 5 },
      material_code: "stainless_304",
      thickness_mm: 10,
    };
    expect(validateExportSheet(req, bakedSpec).map((e) => e.code)).not.toContain(
      "MATERIAL_NOT_ALLOWED",
    );
    const all = [...validateExportBends(req, bakedSpec), ...validateExportSheet(req, bakedSpec)];
    expect(all.filter((e) => e.code === "MATERIAL_NOT_ALLOWED")).toHaveLength(1);
  });

  it("та сама пара, розгортка 400+250+400 > 1000 мм → SHEET_EXCEEDS_MAX_LENGTH не губиться (контрприклади Argon до #273)", () => {
    const req: ExportRequest = {
      template_slug: "z_bracket",
      parameters: {
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        top_flange_mm: 400,
        bottom_flange_mm: 400,
        offset_mm: 250,
        bend_radius_mm: 5,
        width_mm: 100,
      },
      material_code: "stainless_304",
      thickness_mm: 10,
    };
    expect(validateExportSheet(req, bakedSpec).map((e) => e.code)).toEqual([
      "SHEET_EXCEEDS_MAX_LENGTH",
    ]);
  });
});

describe("sheetDimensionsFor — K за матеріалом у кожному шаблоні (рецензія Flash до PR #260)", () => {
  // Мутант «kFactor = 0.40 для <шаблону>» у sheetDimensionsFor раніше виживав:
  // поза l_bracket/z_bracket гейт перевірявся лише на cold_rolled_steel (K=0.40).
  // Алюміній (K=0.33 при R/t=1.25) скорочує кожен гиб — сума габаритів менша.
  const cases: ReadonlyArray<[ExportRequest["template_slug"], ExportRequest["parameters"]]> = [
    ["l_bracket", L_BRACKET_DEFAULT_PARAMETERS],
    ["z_bracket", Z_BRACKET_DEFAULT_PARAMETERS],
    ["corner_angle", CORNER_ANGLE_DEFAULT_PARAMETERS],
    ["wall_shelf", WALL_SHELF_DEFAULT_PARAMETERS],
    ["perforated_panel", PERFORATED_PANEL_DEFAULT_PARAMETERS],
    ["enclosed_shelf", ENCLOSED_SHELF_DEFAULT_PARAMETERS],
  ];

  it.each(cases)("%s: aluminum_5754 дає меншу заготовку за cold_rolled_steel", (slug, defaults) => {
    const dims = (material_code: string) => {
      const req = {
        template_slug: slug,
        parameters: { ...defaults, bend_radius_mm: 2.5 },
        material_code,
        thickness_mm: 2,
      } as ExportRequest;
      const d = sheetDimensionsFor(req, bakedSpec);
      expect(d).not.toBeNull();
      return d!.widthMm + d!.heightMm;
    };
    expect(dims("aluminum_5754")).toBeLessThan(dims("cold_rolled_steel") - 1e-3);
  });
});
