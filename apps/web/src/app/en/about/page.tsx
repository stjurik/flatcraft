import { AboutContent } from "../../../components/about-content";
import { dictionaries } from "../../../i18n/dictionaries";
import { mirroredAlternates } from "../../../i18n/hreflang";

export const metadata = {
  title: dictionaries.en.about.metaTitle,
  description: dictionaries.en.about.metaDescription,
  alternates: mirroredAlternates("en", "/about"),
};

export default function AboutPageEn() {
  return <AboutContent locale="en" />;
}
