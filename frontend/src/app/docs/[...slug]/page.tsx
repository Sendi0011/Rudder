import { notFound } from "next/navigation";
import DocsShell, { docBySlug, staticDocParams } from "@/components/DocsShell";

export const dynamicParams = false;

export function generateStaticParams() {
  return staticDocParams();
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const doc = docBySlug(slug.join("/"));
  return { title: doc?.title ?? "Docs", description: doc ? `Rudder documentation: ${doc.title}` : undefined };
}

export default async function DocsPage({ params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const doc = docBySlug(slug.join("/"));
  if (!doc) notFound();
  return (
    <div className="pt-12 sm:pt-16">
      <h1 className="page-title">{doc.title}</h1>
      <div className="mt-10">
        <DocsShell doc={doc} />
      </div>
    </div>
  );
}
