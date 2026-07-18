import { CatalogContent, parseTab } from "../../../components/catalog-content";
import { dictionaries } from "../../../i18n/dictionaries";
import { mirroredAlternates } from "../../../i18n/hreflang";

export const metadata = {
  title: dictionaries.en.catalog.metaTitle,
  description: dictionaries.en.catalog.metaDescription,
  alternates: mirroredAlternates("en", "/templates"),
};

interface SearchParams {
  readonly tab?: string;
}

export default async function TemplatesPageEn({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const { tab: rawTab } = await searchParams;
  return <CatalogContent tab={parseTab(rawTab)} locale="en" />;
}
