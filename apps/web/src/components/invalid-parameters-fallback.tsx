import type { ProfileIssue } from "@flatcraft/cad-engine";

interface InvalidParametersFallbackProps {
  readonly issues: readonly ProfileIssue[];
}

/**
 * Fallback замість 3D-сцени, коли параметри геометрично невалідні (Hotfix
 * 2.9.f, ADR-026). Render-gate у viewport'ах не монтує `<Canvas>` доти, доки
 * `validateProfile` повертає issues — це первинний захист від крашу R3F, а не
 * лише ErrorBoundary-backstop. Кожен issue показуємо як конкретну пораду
 * українською (issue.message уже містить «…до мінімум X.X мм»).
 */
export function InvalidParametersFallback({ issues }: InvalidParametersFallbackProps) {
  return (
    <div
      role="status"
      data-testid="invalid-parameters-fallback"
      className="bg-surface-sunken text-fg flex h-full w-full flex-col items-center justify-center gap-3 p-6 text-center"
    >
      <span aria-hidden className="text-3xl">
        📐
      </span>
      <p className="text-sm font-medium">Виправте параметри у формі</p>
      {issues.length > 0 ? (
        <ul className="text-fg-muted max-w-xs list-disc text-left text-xs marker:text-current">
          {issues.map((issue) => (
            <li key={issue.which}>{issue.message}</li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
