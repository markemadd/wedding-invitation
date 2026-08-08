import { listWishes } from "./actions";
import Invitation from "@/components/Invitation";

/** Wishes are read on the server so the first paint already has them. */
export const revalidate = 30;

export default async function Page() {
  const wishes = await listWishes();
  return <Invitation wishes={wishes} />;
}
