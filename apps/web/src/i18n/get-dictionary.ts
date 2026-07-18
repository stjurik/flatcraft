import { dictionaries, type Dictionary } from "./dictionaries";
import type { Locale } from "./locale";

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale];
}
