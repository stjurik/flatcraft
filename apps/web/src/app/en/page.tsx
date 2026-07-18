import type { Metadata } from "next";

import { HomeContent } from "../../components/home-content";
import { dictionaries } from "../../i18n/dictionaries";
import { mirroredAlternates } from "../../i18n/hreflang";

const dict = dictionaries.en;

export const metadata: Metadata = {
  title: dict.common.siteTitle,
  description: dict.common.siteDescription,
  alternates: mirroredAlternates("en", "/"),
  openGraph: {
    type: "website",
    locale: dict.common.ogLocale,
    title: dict.common.siteTitle,
    description: dict.common.siteDescription,
  },
  twitter: {
    card: "summary_large_image",
    title: dict.common.siteTitle,
    description: dict.common.siteDescription,
  },
};

export default function HomePageEn() {
  return <HomeContent locale="en" />;
}
