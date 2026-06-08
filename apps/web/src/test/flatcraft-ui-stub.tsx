/**
 * Vitest-стаб для `@flatcraft/ui` (Hotfix 2.9.c).
 *
 * Чому: барель `@flatcraft/ui` ре-експортує R3F 3d-viewport, а vitest (node, без
 * WebGL) резолвить пакет із `dist` — крихко щодо порядку turbo-build. Жоден web
 * unit-тест не вживає реальний `@flatcraft/ui`, окрім editor-wrapper тестів, яким
 * потрібні лише `AutoForm` (рендер-плейсхолдер) і `zodIssuesToFieldErrors`.
 *
 * Аліас на цей файл (apps/web/vitest.config.ts) робить резолюцію детермінованою
 * і незалежною від dist. Типи у typecheck беруться з РЕАЛЬНОГО пакета (tsc через
 * tsconfig paths → packages/ui/src), тож контракт лишається перевіреним.
 *
 * ⚠ Якщо майбутній web unit-тест потребуватиме справжній компонент із
 * `@flatcraft/ui` — приберіть/звузьте аліас і застабте конкретний підмодуль.
 */
export function AutoForm(): null {
  return null;
}

export function zodIssuesToFieldErrors(): Record<string, string> {
  return {};
}
