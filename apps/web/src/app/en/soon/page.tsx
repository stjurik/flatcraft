import { SoonContent } from "../../../components/soon-content";
import { dictionaries } from "../../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.en.soon.metaTitle,
};

export default function SoonPageEn() {
  return <SoonContent locale="en" />;
}
