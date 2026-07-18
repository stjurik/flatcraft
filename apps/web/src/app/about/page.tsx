import { AboutContent } from "../../components/about-content";
import { dictionaries } from "../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.uk.about.metaTitle,
  description: dictionaries.uk.about.metaDescription,
};

export default function AboutPage() {
  return <AboutContent locale="uk" />;
}
