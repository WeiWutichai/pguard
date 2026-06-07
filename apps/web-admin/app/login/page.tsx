import { redirect } from "next/navigation";

import { getServerSession } from "@/lib/session";
import { LoginForm } from "./login-form";

// Public login route (outside the (dashboard) group). If an admin session already exists, skip the
// form and go straight to the dashboard. A non-admin session is NOT redirected (the dashboard gate
// would bounce it right back to /login → a loop) — they just see the form to sign in as an admin.
export default async function LoginPage() {
  const user = await getServerSession();
  if (user?.role === "admin") redirect("/dashboard");
  return <LoginForm />;
}
