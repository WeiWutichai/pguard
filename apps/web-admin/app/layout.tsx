// pguard v2 scaffold stub — root layout (App Router).
// TODO(CLAUDE.md › Bilingual TH/EN): wire a locale provider here and drive the
// <html lang> attribute from the active locale (th | en). The TH/EN switch should
// set a cookie (httpOnly is not required for the locale itself) and re-render.
// TODO(CLAUDE.md › Web (Next.js)): auth state is read from httpOnly cookies on the
// server (never localStorage); pass session info down via server components.
import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  title: "pguard admin",
  description: "pguard v2 web admin — guard onboarding, payments, operations",
};

export default function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  // TODO: resolve active locale (th | en) from cookie and set lang accordingly.
  const lang = "en";

  return (
    <html lang={lang}>
      <body>{children}</body>
    </html>
  );
}
