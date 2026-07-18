import { AboutContent } from "../../components/about-content";
import { dictionaries } from "../../i18n/dictionaries";
import { mirroredAlternates } from "../../i18n/hreflang";

export const metadata = {
  title: dictionaries.uk.about.metaTitle,
  description: dictionaries.uk.about.metaDescription,
  alternates: mirroredAlternates("uk", "/about"),
};

export default function AboutPage() {
  return <AboutContent locale="uk" />;
}
