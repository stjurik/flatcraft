import { CatalogContent, parseTab } from "../../components/catalog-content";
import { dictionaries } from "../../i18n/dictionaries";
import { mirroredAlternates } from "../../i18n/hreflang";

export const metadata = {
  title: dictionaries.uk.catalog.metaTitle,
  description: dictionaries.uk.catalog.metaDescription,
  alternates: mirroredAlternates("uk", "/templates"),
};

interface SearchParams {
  readonly tab?: string;
}

export default async function TemplatesPage({
  searchParams,
}: {
  // Next.js 15 App Router: searchParams — Promise<...>.
  searchParams: Promise<SearchParams>;
}) {
  const { tab: rawTab } = await searchParams;
  return <CatalogContent tab={parseTab(rawTab)} locale="uk" />;
}
