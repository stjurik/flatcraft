/**
 * ⚠️  ЗГЕНЕРОВАНО АВТОМАТИЧНО — НЕ РЕДАГУВАТИ ВРУЧНУ.
 *
 * Джерело: packages/cad-engine/data/bend-machine-esi.yaml
 * Генератор: tools/scripts/bake-bend-matrix.ts (prebuild, ADR-022).
 *
 * Browser-safe snapshot bend-machine spec для клієнтської валідації матриці
 * гибу (Hotfix 2.9.c). Щоб змінити — правте YAML і запустіть bake, не цей файл.
 */

import type { BendMachineSpec } from "../spec.js";

export const bakedSpec: BendMachineSpec = {
  "machine": {
    "vendor": "ТОВ ЕСІ ПРОММЕТАЛ",
    "model": "reference-100t",
    "source": "docs/07_BEND_MACHINE_SPEC.md",
    "source_date": "2026-05-08"
  },
  "global": {
    "max_force_t": 100,
    "min_flange_mm": 7.5,
    "angle_tolerance_deg": 0.25,
    "allowed_angles_deg": [
      30,
      45,
      60,
      90,
      120,
      135
    ],
    "default_angle_deg": 90
  },
  "material_groups": {
    "carbon_and_stainless_and_alu_and_galv": {
      "members": [
        "cold_rolled_steel",
        "hot_rolled_steel",
        "stainless_304",
        "stainless_430",
        "aluminum_5754",
        "aluminum_amg3",
        "galvanized_steel"
      ]
    },
    "carbon_alu_galv_only": {
      "members": [
        "cold_rolled_steel",
        "hot_rolled_steel",
        "aluminum_5754",
        "aluminum_amg3",
        "galvanized_steel"
      ]
    }
  },
  "capability_matrix": [
    {
      "thickness_mm": 1,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        1,
        2.5
      ],
      "max_bend_length_mm": 3000
    },
    {
      "thickness_mm": 1.5,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        1,
        2.5,
        4
      ],
      "max_bend_length_mm": 3000,
      "notes": {
        "r4_no_holes_near_bend_line": true
      }
    },
    {
      "thickness_mm": 1.8,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        1,
        2.5,
        4
      ],
      "max_bend_length_mm": 3000,
      "notes": {
        "r4_no_holes_near_bend_line": true
      }
    },
    {
      "thickness_mm": 2,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        1,
        2.5,
        4
      ],
      "max_bend_length_mm": 3000,
      "notes": {
        "r4_no_holes_near_bend_line": true
      }
    },
    {
      "thickness_mm": 2.5,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        2.5,
        4
      ],
      "max_bend_length_mm": 3000,
      "notes": {
        "r4_no_holes_near_bend_line": true
      }
    },
    {
      "thickness_mm": 3,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        2.5,
        4
      ],
      "max_bend_length_mm": 3000,
      "notes": {
        "r4_no_holes_near_bend_line": true
      }
    },
    {
      "thickness_mm": 4,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        2.5,
        4
      ],
      "max_bend_length_mm": 2500
    },
    {
      "thickness_mm": 5,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        4,
        5
      ],
      "max_bend_length_mm": 2500
    },
    {
      "thickness_mm": 6,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        4,
        5
      ],
      "max_bend_length_mm": 2300
    },
    {
      "thickness_mm": 8,
      "group": "carbon_and_stainless_and_alu_and_galv",
      "allowed_inner_radius_mm": [
        5
      ],
      "max_bend_length_mm": 1000
    },
    {
      "thickness_mm": 10,
      "group": "carbon_alu_galv_only",
      "allowed_inner_radius_mm": [
        5
      ],
      "inner_radius_max_mm": 1000,
      "max_bend_length_mm": 1000
    }
  ],
  "k_factor": {
    "default_by_material": {
      "cold_rolled_steel": 0.4,
      "hot_rolled_steel": 0.42,
      "galvanized_steel": 0.4,
      "stainless_304": 0.45,
      "stainless_430": 0.44,
      "aluminum_5754": 0.33,
      "aluminum_amg3": 0.33,
      "copper": 0.38,
      "brass": 0.38
    },
    "ratio_correction": [
      {
        "ratio_min": 0,
        "ratio_max": 1,
        "multiplier": 0.85
      },
      {
        "ratio_min": 1,
        "ratio_max": 3,
        "multiplier": 1
      },
      {
        "ratio_min": 3,
        "ratio_max": 999,
        "multiplier": 1.1
      }
    ]
  },
  "hole_to_bend_distance": {
    "formula": "a * thickness_mm + inner_radius_mm",
    "coefficient_by_material": {
      "cold_rolled_steel": 2,
      "hot_rolled_steel": 2.5,
      "galvanized_steel": 2,
      "stainless_304": 2.5,
      "stainless_430": 2.5,
      "aluminum_5754": 1.5,
      "aluminum_amg3": 1.5,
      "copper": 1.5,
      "brass": 1.5
    }
  }
};
