import { AboutContent } from "../../../components/about-content";
import { dictionaries } from "../../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.en.about.metaTitle,
  description: dictionaries.en.about.metaDescription,
};

export default function AboutPageEn() {
  return <AboutContent locale="en" />;
}
