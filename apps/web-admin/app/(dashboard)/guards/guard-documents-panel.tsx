"use client";

import { useEffect, useState } from "react";

import { profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY, GUARD_DOC_TYPES, type GuardDocType } from "./copy";

/**
 * The guard's six credential documents, read for an admin. `GET /profile/guard/{id}/documents`
 * is owner-or-admin, so the admin reviewer reads any guard's images here. Each type is probed
 * concurrently — a 404 / error means "not uploaded yet" (honest, never a fabricated image). The
 * server returns a short-lived (~1h) presigned URL; the raw S3 key is never exposed. This is the
 * admin-side counterpart to the guard's own mobile documents screen (where uploads happen).
 */
export function GuardDocumentsPanel({ userId }: { userId: string }) {
  const { lang } = useLanguage();
  const c = COPY[lang];
  const [urls, setUrls] = useState<Partial<Record<GuardDocType, string>>>({});
  const [loading, setLoading] = useState(true);

  // The modal mounts this with `key={userId}`, so a fresh guard gets fresh initial state — no
  // synchronous reset in the effect (which trips react-hooks/set-state-in-effect).
  useEffect(() => {
    let alive = true;
    Promise.all(
      GUARD_DOC_TYPES.map((dt) =>
        profileApi
          .GET("/profile/guard/{user_id}/documents", {
            params: { path: { user_id: userId }, query: { document_type: dt } },
          })
          // A 404 (valid type, not uploaded) or any read error → null = not uploaded; the whole
          // panel never fails on one missing type.
          .then(({ data, error }) => (error ? null : (data?.data?.download_url ?? null)))
          .catch(() => null),
      ),
    ).then((results) => {
      if (!alive) return;
      const next: Partial<Record<GuardDocType, string>> = {};
      GUARD_DOC_TYPES.forEach((dt, i) => {
        const url = results[i];
        if (url) next[dt] = url;
      });
      setUrls(next);
      setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, [userId]);

  return (
    <div className="mt-4 rounded-lg border border-border">
      <div className="border-b border-border px-4 py-3 text-xs font-semibold uppercase tracking-[0.04em] text-muted">
        {c.docsHead}
      </div>
      {loading ? (
        <div className="px-4 py-6 text-center text-[13px] text-muted">{c.docsLoading}</div>
      ) : (
        <div className="grid grid-cols-3 gap-3 p-4">
          {GUARD_DOC_TYPES.map((dt) => (
            <DocCell
              key={dt}
              label={c.docLabels[dt]}
              url={urls[dt]}
              notUploaded={c.docsNotUploaded}
              openLabel={c.docOpen}
            />
          ))}
        </div>
      )}
    </div>
  );
}

/** One credential cell: a thumbnail linking to the full presigned image, or an honest
 *  "not uploaded" placeholder. If the inline image fails to load (expired/unreachable URL), it
 *  degrades to an "open full" link rather than a broken-image glyph. */
function DocCell({
  label,
  url,
  notUploaded,
  openLabel,
}: {
  label: string;
  url?: string;
  notUploaded: string;
  openLabel: string;
}) {
  const [imgError, setImgError] = useState(false);

  return (
    <div className="flex flex-col gap-1.5">
      <div className="text-[11.5px] font-medium text-muted">{label}</div>
      {url ? (
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          title={openLabel}
          className="group block h-24 w-full overflow-hidden rounded-md border border-border"
        >
          {imgError ? (
            <span className="flex h-full w-full items-center justify-center text-[11px] font-medium text-text-strong underline">
              {openLabel}
            </span>
          ) : (
            // eslint-disable-next-line @next/next/no-img-element -- presigned S3 URL, not a static asset
            <img
              src={url}
              alt={label}
              onError={() => setImgError(true)}
              className="h-full w-full object-cover transition group-hover:opacity-90"
            />
          )}
        </a>
      ) : (
        <div className="flex h-24 w-full items-center justify-center rounded-md border border-dashed border-border-strong text-[11px] text-faint">
          {notUploaded}
        </div>
      )}
    </div>
  );
}
