import { SoonContent } from "../../components/soon-content";
import { dictionaries } from "../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.uk.soon.metaTitle,
};

/**
 * Заглушка для placeholder-маршрутів (Discord, Telegram, /unlock,
 * /privacy, /terms, /cookies — Phase 2.12.b). Реальні сторінки прийдуть
 * у Phase 3+ (auth/donations) і Phase 5 (legal docs).
 */
export default function SoonPage() {
  return <SoonContent locale="uk" />;
}
