import { redirect } from "next/navigation";

// Root entry → the dashboard. The (dashboard) layout resolves the session server-side and bounces
// to /login when there's no valid auth cookie.
export default function RootPage() {
  redirect("/dashboard");
}
