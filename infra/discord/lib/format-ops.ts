import type { DiffOp } from "./diff.js";

// Pure: DiffOp[] → людиночитний вивід для scripts/diff.ts і логів apply.

function describeFields(fields: Record<string, { from: unknown; to: unknown }>): string {
  return Object.entries(fields)
    .map(([key, { from, to }]) => `${key}: ${JSON.stringify(from)} → ${JSON.stringify(to)}`)
    .join("; ");
}

export function formatOps(ops: DiffOp[]): string {
  if (ops.length === 0) return "✅ немає drift — Discord відповідає config'у.";

  const lines = ops.map((op) => {
    switch (op.type) {
      case "create":
        return `+ create ${op.entity} ${op.target}`;
      case "update":
        return `~ update ${op.entity} ${op.target} (${describeFields(op.fields)})`;
      case "reorder":
        return `↕ reorder ${op.entity}: ${op.order.join(" > ")}`;
      case "orphan":
        return (
          `! orphan ${op.entity} ${op.target} — є у Discord, нема у config. ` +
          `apply НЕ видалить: приберіть вручну або додайте у config/*.ts.`
        );
    }
  });

  const counts = {
    create: ops.filter((op) => op.type === "create").length,
    update: ops.filter((op) => op.type === "update").length,
    reorder: ops.filter((op) => op.type === "reorder").length,
    orphan: ops.filter((op) => op.type === "orphan").length,
  };

  return [
    ...lines,
    "",
    `Разом: ${counts.create} create, ${counts.update} update, ${counts.reorder} reorder, ${counts.orphan} orphan.`,
  ].join("\n");
}
