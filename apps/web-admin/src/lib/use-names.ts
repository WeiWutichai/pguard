"use client";

// Admin display-name resolver — the single client for `POST /admin/users/resolve` (profile),
// which maps user_ids → { role, display_name } for guards + customers in ONE batch call (no
// per-row N+1). The endpoint OMITS ids it can't resolve (admins have no stored name; unknown /
// deleted ids); those fall back to a localized role label + short id. Display names here are
// admin-only PII — never logged or surfaced outside the admin SPA.

import { useCallback, useEffect, useMemo, useState } from "react";

import type { components } from "@/api/generated/profile";
import { profileApi } from "@/lib/api";
import type { Lang } from "@/lib/lang";

type ResolvedName = components["schemas"]["ResolvedName"];

/** Endpoint cap (profile RESOLVE_NAMES_LIMIT): max ids per call. Larger batches are chunked. */
const RESOLVE_LIMIT = 500;

/** Localized role labels for the fallback (when an id resolves to a profile role but has no name,
 * or is an admin/unknown id the resolver omitted). Mirrors the resolver's `role` enum + an admin
 * label for omitted ids (the flagged identity.display_name follow-up). */
const ROLE_LABEL: Record<Lang, { guard: string; customer: string; admin: string }> = {
  th: { guard: "เจ้าหน้าที่", customer: "ลูกค้า", admin: "แอดมิน" },
  en: { guard: "Guard", customer: "Customer", admin: "Admin" },
};

/** First 8 chars of a uuid for the short-id fallback / tooltip ("#e3514af2"). */
export function shortId(id: string): string {
  return `#${id.slice(0, 8)}`;
}

/** What the hook returns per id: the resolved display info, plus the rendered `label` (name, or a
 * role-label + short-id fallback) and a `title` (the full id) for the tooltip. */
export interface ResolvedDisplay {
  /** The resolved display name, or null (mid-onboarding, or no profile row → omitted). */
  name: string | null;
  /** "guard" | "customer" when the resolver returned a row; null for omitted ids (admin/unknown). */
  role: ResolvedName["role"] | null;
  /** Ready-to-render text: the name when known, else a localized role-label + short id. */
  label: string;
  /** Full id for a tooltip/title attribute (keep the short-id fallback discoverable). */
  title: string;
}

/** How to label an id the resolver OMITTED (no profile row). On the Activity admin column an
 * omitted id is the acting admin → "Admin #id" (the flagged identity.display_name follow-up). On
 * customer/guard columns an omitted id is an unknown/deleted user → bare short id (never "Admin"). */
export type OmittedFallback = "admin" | "short-id";

/** A resolved id carries a row; an *attempted-but-omitted* id is recorded as `null` so it is not
 * re-requested every render (the resolver omits admins/unknown — those never gain a row). */
type ResolveState = Record<string, ResolvedName | null>;

/**
 * Batch-resolve a page's user_ids to display names. Pass every id the page needs (customer, guard,
 * caller, callee, admin — mixed is fine; non-uuid / empty entries are ignored). The hook de-dupes,
 * chunks to the endpoint cap, fetches once per id-set change, and hands back a `resolve(id)` lookup
 * plus a `loading` flag. Resolution is best-effort enrichment: on error the page still renders the
 * short-id fallback (never blocks the screen).
 */
export function useNameResolver(
  ids: ReadonlyArray<string | null | undefined>,
  lang: Lang,
  omittedFallback: OmittedFallback = "short-id",
) {
  // id → row (resolved) | null (attempted, omitted by the resolver). `undefined` (absent key) means
  // not-yet-fetched. Tracking attempted-misses in state keeps `pending` derivable without a ref.
  const [state, setState] = useState<ResolveState>({});
  const [loading, setLoading] = useState(false);

  // Stable, sorted, de-duped key of the ids that still need fetching. Sorting makes the dep
  // order-insensitive so a reordered list (e.g. after a filter) doesn't refetch. Derived purely
  // from props + state (no render-time ref reads).
  const pendingKey = useMemo(() => {
    const out = new Set<string>();
    for (const id of ids) {
      if (id && !(id in state)) out.add(id);
    }
    return Array.from(out).sort().join(",");
  }, [ids, state]);

  useEffect(() => {
    if (pendingKey === "") return;
    let alive = true;
    const batch = pendingKey.split(",");

    const chunks: string[][] = [];
    for (let i = 0; i < batch.length; i += RESOLVE_LIMIT) {
      chunks.push(batch.slice(i, i + RESOLVE_LIMIT));
    }

    // Defer the loading flag out of the effect's synchronous body (React-compiler lint), then run
    // the batch. Each attempted id is written back — as its row, or `null` if the resolver omitted
    // it — so the next render no longer treats it as pending.
    const flag = setTimeout(() => alive && setLoading(true), 0);
    Promise.all(
      chunks.map((chunk) =>
        profileApi
          .POST("/admin/users/resolve", { body: { ids: chunk } })
          .then(({ data }) => data?.data ?? {})
          .catch(() => ({}) as Record<string, ResolvedName>),
      ),
    )
      .then((results) => {
        if (!alive) return;
        const merged: Record<string, ResolvedName> = {};
        for (const r of results) Object.assign(merged, r);
        setState((prev) => {
          const next = { ...prev };
          for (const id of batch) next[id] = merged[id] ?? null; // null = attempted, omitted
          return next;
        });
        setLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setLoading(false);
      });

    return () => {
      alive = false;
      clearTimeout(flag);
    };
  }, [pendingKey]);

  const resolve = useCallback(
    (id: string | null | undefined): ResolvedDisplay => {
      if (!id) {
        return { name: null, role: null, label: "—", title: "" };
      }
      const hit = state[id];
      if (hit?.display_name) {
        return { name: hit.display_name, role: hit.role, label: hit.display_name, title: id };
      }
      // Row exists but no name yet (mid-onboarding) → role label + short id; role still authoritative.
      if (hit) {
        const roleLabel = ROLE_LABEL[lang][hit.role];
        return { name: null, role: hit.role, label: `${roleLabel} ${shortId(id)}`, title: id };
      }
      // Not-yet-fetched, or omitted by the resolver (admin / unknown / deleted) → per-screen
      // fallback: the admin label on the Activity admin column, else a bare short id.
      const label =
        omittedFallback === "admin" ? `${ROLE_LABEL[lang].admin} ${shortId(id)}` : shortId(id);
      return { name: null, role: null, label, title: id };
    },
    [state, lang, omittedFallback],
  );

  return { resolve, loading };
}
