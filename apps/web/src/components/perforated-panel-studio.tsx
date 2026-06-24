"use client";

import { type MaterialChoice } from "@flatcraft/types";
import { useMemo, useState } from "react";

import {
  schemaForHoleShape,
  slugForHoleShape,
  type HoleShape,
  type PerforationParameters,
} from "../lib/perforation-shape";

import { PerforatedPanelEditor } from "./perforated-panel-editor";
import { PerforatedPanelSquareViewport } from "./perforated-panel-square-viewport";
import { PerforatedPanelViewport } from "./perforated-panel-viewport";
import { TemplateStudio, type TemplateStudioProductMeta } from "./template-studio";

interface PerforatedPanelStudioProps {
  /** Стартова форма отвору (з slug роута або базового шаблону продукту). */
  readonly initialHoleShape: HoleShape;
  /** Стартові params з ОБОМА ключами розміру (див. initialPerforationParams). */
  readonly initialParameters: PerforationParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly product?: TemplateStudioProductMeta;
}

/**
 * Спільна студія перфо-панелі з клієнтським перемикачем форми отвору
 * (круг ↔ квадрат) — Варіант B (над двома шаблонами, без змін backend).
 *
 * `holeShape` піднятий сюди й керує похідними `templateSlug` / `schema` /
 * `renderViewport`. `TemplateStudio` лишається ЗМОНТОВАНИМ при перемиканні
 * (змінюються лише props), тож params + вибір матеріалу зберігаються. Значення
 * розміру отвору синхронізоване в обидва ключі редактором (`syncHoleKeys`).
 *
 * Без гибів → TemplateStudio пропускає bend-matrix і profile-валідацію.
 */
export function PerforatedPanelStudio({
  initialHoleShape,
  initialParameters,
  materials,
  product,
}: PerforatedPanelStudioProps) {
  const [holeShape, setHoleShape] = useState<HoleShape>(initialHoleShape);
  const slug = slugForHoleShape(holeShape);
  const schema = useMemo(() => schemaForHoleShape(holeShape), [holeShape]);

  return (
    <TemplateStudio<PerforationParameters>
      mode={product ? "product" : "part"}
      templateSlug={slug}
      initialParameters={initialParameters}
      materials={materials}
      schema={schema}
      testId="perforated-panel-studio"
      {...(product ? { product } : {})}
      renderEditor={(props) => (
        <PerforatedPanelEditor
          value={props.value}
          onChange={props.onChange}
          holeShape={holeShape}
          onHoleShapeChange={setHoleShape}
          {...(props.visibleFields ? { visibleFields: props.visibleFields } : {})}
        />
      )}
      renderViewport={(props) =>
        holeShape === "square" ? (
          <PerforatedPanelSquareViewport
            parameters={props.parameters}
            thicknessMm={props.thicknessMm}
          />
        ) : (
          <PerforatedPanelViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
        )
      }
    />
  );
}
