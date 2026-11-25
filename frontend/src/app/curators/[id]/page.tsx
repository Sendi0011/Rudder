import CuratorDetail from "@/components/CuratorDetail";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CuratorDetail id={Number(id)} />;
}
