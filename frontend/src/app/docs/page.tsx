import DocsShell, { docBySlug } from "@/components/DocsShell";

export const metadata = {
  title: "Documentation",
  description: "Rendered project documentation for Rudder.",
};

export default function DocsIndexPage() {
  const doc = docBySlug("index");
  if (!doc) return null;
  return (
    <div className="pt-12 sm:pt-16">
      <h1 className="page-title">Documentation</h1>
      <div className="mt-10">
        <DocsShell doc={doc} />
      </div>
    </div>
  );
}
