import { CatalogContent, parseTab } from "../../../components/catalog-content";
import { dictionaries } from "../../../i18n/dictionaries";

export const metadata = {
  title: dictionaries.en.catalog.metaTitle,
  description: dictionaries.en.catalog.metaDescription,
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
