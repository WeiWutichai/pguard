import "./globals.css";

import type { Metadata } from "next";
import type { ReactNode } from "react";
import { cookies } from "next/headers";

import { LanguageProvider } from "@/lib/i18n";
import { LANG_COOKIE, parseLang } from "@/lib/lang";

export const metadata: Metadata = {
  title: "pguard admin",
  description: "pguard v2 web admin — guard onboarding, payments, operations",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  // Resolve the active locale from the non-sensitive `lang` cookie (server-read so the markup
  // matches the client provider — no hydration mismatch). Auth itself is the httpOnly
  // `access_token` cookie, validated server-side in the (dashboard) layout.
  const lang = parseLang((await cookies()).get(LANG_COOKIE)?.value);

  return (
    <html lang={lang}>
      <body>
        <LanguageProvider initialLang={lang}>{children}</LanguageProvider>
      </body>
    </html>
  );
}
