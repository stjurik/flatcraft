import { SoonContent } from "../../../components/soon-content";
import { dictionaries } from "../../../i18n/dictionaries";
import { mirroredAlternates } from "../../../i18n/hreflang";

export const metadata = {
  title: dictionaries.en.soon.metaTitle,
  alternates: mirroredAlternates("en", "/soon"),
};

export default function SoonPageEn() {
  return <SoonContent locale="en" />;
}
