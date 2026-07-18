import type { Metadata } from "next";

import { HomeContent } from "../components/home-content";
import { mirroredAlternates } from "../i18n/hreflang";

export const metadata: Metadata = {
  alternates: mirroredAlternates("uk", "/"),
};

export default function HomePage() {
  return <HomeContent locale="uk" />;
}
