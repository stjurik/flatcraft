/**
 * Re-export radix Dialog як namespace `Dialog` (Root/Trigger/Portal/Overlay/
 * Content/Title/Description/Close). Сирий @radix-ui/react-dialog лежить у
 * залежностях @flatcraft/ui — споживачі (apps/web) тягнуть лише через нас.
 */
export * as Dialog from "@radix-ui/react-dialog";
