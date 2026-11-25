import CuratorDetail from "@/components/CuratorDetail";
import { snapshot } from "@/lib/snapshot";

export const dynamicParams = false;

export function generateStaticParams() {
  return snapshot.curators.map((entry) => ({ id: String(entry.id) }));
}

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const entry = snapshot.curators.find((curator) => curator.id === Number(id));
  return (
    <>
      <h1 className="sr-only">{entry ? `Curator ${entry.curator}` : `Strategy ${id}`}</h1>
      <CuratorDetail id={Number(id)} />
    </>
  );
}
