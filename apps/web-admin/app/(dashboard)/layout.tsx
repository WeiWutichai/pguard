import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { getServerSession } from "@/lib/session";
import { AuthProvider } from "@/components/auth-provider";
import { Sidebar } from "@/components/shell/sidebar";
import { Topbar } from "@/components/shell/topbar";

// Server-side auth + role gate for every dashboard route: resolve the session from the httpOnly
// cookie and redirect to /login when there's no session OR the user isn't an admin (this is an
// admin-only console — a logged-in customer/guard must not land in the shell; defence beyond the
// backend's 403). No flash of the dashboard. The user is handed to a client AuthProvider.
export default async function DashboardLayout({
  children,
}: {
  children: ReactNode;
}) {
  const user = await getServerSession();
  if (!user || user.role !== "admin") redirect("/login");

  return (
    <AuthProvider user={user}>
      {/* admin.css `.app` (248px | 1fr) + `.main` + `.content` (26px 28px 60px padding). */}
      <div className="flex h-screen">
        <Sidebar />
        <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <Topbar />
          <main className="min-h-0 flex-1 overflow-y-auto bg-app px-7 pb-[60px] pt-[26px]">
            {children}
          </main>
        </div>
      </div>
    </AuthProvider>
  );
}
