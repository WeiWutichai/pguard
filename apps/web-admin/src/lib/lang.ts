// Server-safe locale primitives — NO "use client". The root layout (a Server Component) reads the
// `lang` cookie and must call parseLang() server-side; importing it from the "use client" i18n
// module crosses the RSC boundary (Next rejects calling a client function from the server). Keeping
// the type + cookie name + parser here lets both the server layout and the client i18n provider use
// them. i18n.tsx re-exports these for existing client-side imports.

/** UI languages. The app is bilingual; Thai is the primary market. */
export type Lang = "th" | "en";

/** Non-sensitive cookie that carries the chosen locale (read on both server and client). */
export const LANG_COOKIE = "lang";

/** Parse a `lang` cookie value into a valid [Lang], defaulting to Thai (the primary market). */
export function parseLang(value: string | undefined): Lang {
  return value === "en" ? "en" : "th";
}
