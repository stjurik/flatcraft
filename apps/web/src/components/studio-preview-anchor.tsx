/**
 * «↓ 3D-прев'ю» — anchor-кнопка, видима лише на mobile/tablet, де
 * editor і viewport стекаються вертикально. Скрол до canvas-секції
 * за один тап, щоб користувач не шукав прев'ю після кожної зміни
 * параметра.
 *
 * На `lg:` (≥1024px) виходить 2-колонний grid (editor зліва, viewport
 * праворуч завжди видно), тож anchor приховуємо.
 *
 * Цільовий id — `studio-viewport`, який кожен `XViewport` виставляє
 * на root-обгортці.
 */
export function StudioPreviewAnchor() {
  return (
    <a
      href="#studio-viewport"
      data-testid="studio-preview-anchor"
      className="text-fg-muted hover:text-fg border-border min-h-tap inline-flex items-center justify-center self-start rounded-sm border px-3 text-sm font-medium lg:hidden"
    >
      ↓ Подивитися 3D-прев'ю
    </a>
  );
}
