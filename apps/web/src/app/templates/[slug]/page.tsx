import { notFound } from "next/navigation";

import { TemplateDetailContent } from "../../../components/template-detail-content";
import { dictionaries } from "../../../i18n/dictionaries";
import { fetchMaterials, fetchTemplate } from "../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const template = await fetchTemplate(slug).catch(() => null);
  return {
    title: template ? `${template.nameUk} · hart` : dictionaries.uk.templateDetail.notFoundTitle,
  };
}

export default async function TemplatePage({ params }: PageProps) {
  const { slug } = await params;
  // Materials і template можна fetch'ити паралельно — обидва server-side.
  const [template, materials] = await Promise.all([fetchTemplate(slug), fetchMaterials()]);
  if (!template) notFound();

  return <TemplateDetailContent template={template} materials={materials} locale="uk" />;
}
