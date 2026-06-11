import "./globals.css";

import type { Metadata } from "next";
import type { ReactNode } from "react";
import { IBM_Plex_Mono, IBM_Plex_Sans, IBM_Plex_Sans_Thai } from "next/font/google";
import { cookies } from "next/headers";

import { LanguageProvider } from "@/lib/i18n";
import { LANG_COOKIE, parseLang } from "@/lib/lang";

// Design fonts (tokens.css --font-thai/--font-latin/--font-mono). next/font self-hosts
// them (no request to Google at runtime, no FOUT) and exposes each as a CSS variable that
// globals.css threads into the token font stacks. Weights mirror the design's @import.
const plexThai = IBM_Plex_Sans_Thai({
  subsets: ["thai", "latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-plex-thai",
  display: "swap",
});
const plexSans = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  style: ["normal", "italic"],
  variable: "--font-plex",
  display: "swap",
});
const plexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-plex-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "pguard admin",
  description: "pguard v2 web admin — guard onboarding, payments, operations",
};

/** Runs before paint: restores the persisted theme so a dark-mode reload doesn't flash
 * light. Mirrors the hi-fi shell's `pg_theme` localStorage key (admin-shell.js). */
const THEME_BOOT = `try{var t=localStorage.getItem("pg_theme");if(t==="dark")document.documentElement.setAttribute("data-theme","dark")}catch(e){}`;

export default async function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  // Resolve the active locale from the non-sensitive `lang` cookie (server-read so the markup
  // matches the client provider — no hydration mismatch). Auth itself is the httpOnly
  // `access_token` cookie, validated server-side in the (dashboard) layout.
  const lang = parseLang((await cookies()).get(LANG_COOKIE)?.value);

  return (
    // suppressHydrationWarning: the THEME_BOOT script may set data-theme before React hydrates.
    <html
      lang={lang}
      suppressHydrationWarning
      className={`${plexThai.variable} ${plexSans.variable} ${plexMono.variable}`}
    >
      <body>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} />
        <LanguageProvider initialLang={lang}>{children}</LanguageProvider>
      </body>
    </html>
  );
}
