"use client";

import { Button, Dialog } from "@flatcraft/ui";

/**
 * Radix Dialog обгорнутий у наш `Button` — щоб styleguide показав
 * реальну overlay-механіку, не лише статичну візуалку. Toast/Tooltip
 * у styleguide лишаються статичними (економимо залежності до Phase 2.12).
 */
export function DialogDemo() {
  return (
    <Dialog.Root>
      <Dialog.Trigger asChild>
        <Button variant="outline" size="sm">
          Відкрити dialog
        </Button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay
          className="fixed inset-0 z-40"
          style={{ background: "oklch(var(--color-overlay) / 0.6)" }}
        />
        <Dialog.Content className="bg-bg-elevated fixed left-1/2 top-1/2 z-50 w-[90vw] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-lg p-6 shadow-lg">
          <Dialog.Title className="text-fg text-lg font-semibold">Demo Dialog</Dialog.Title>
          <Dialog.Description className="text-fg-muted mt-2 text-sm">
            Це radix-овий dialog із токенами дизайн-системи. Закривається Esc, кліком на overlay,
            або кнопкою нижче.
          </Dialog.Description>
          <div className="mt-4 flex justify-end gap-2">
            <Dialog.Close asChild>
              <Button variant="ghost" size="sm">
                Скасувати
              </Button>
            </Dialog.Close>
            <Dialog.Close asChild>
              <Button variant="default" size="sm">
                ОК
              </Button>
            </Dialog.Close>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
