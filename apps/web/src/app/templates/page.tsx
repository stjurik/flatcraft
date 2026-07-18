import { CatalogContent, parseTab } from "../../components/catalog-content";
import { dictionaries } from "../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.uk.catalog.metaTitle,
  description: dictionaries.uk.catalog.metaDescription,
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
