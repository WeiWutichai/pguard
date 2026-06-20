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
  // The document the admin is previewing full-size IN-PAGE (lightbox), or null. Clicking a
  // thumbnail opens this instead of navigating to a new browser tab.
  const [preview, setPreview] = useState<{ url: string; label: string } | null>(null);

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

  const closeLabel = lang === "th" ? "ปิด" : "Close";

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
              onOpen={(url, label) => setPreview({ url, label })}
            />
          ))}
        </div>
      )}
      {preview && (
        <DocLightbox
          url={preview.url}
          label={preview.label}
          openLabel={c.docOpen}
          closeLabel={closeLabel}
          onClose={() => setPreview(null)}
        />
      )}
    </div>
  );
}

/** One credential cell: a thumbnail that opens a full-size IN-PAGE preview, or an honest
 *  "not uploaded" placeholder. If the inline image fails to load (expired/unreachable URL), it
 *  degrades to an "open full" affordance rather than a broken-image glyph. */
function DocCell({
  label,
  url,
  notUploaded,
  openLabel,
  onOpen,
}: {
  label: string;
  url?: string;
  notUploaded: string;
  openLabel: string;
  onOpen: (url: string, label: string) => void;
}) {
  const [imgError, setImgError] = useState(false);

  return (
    <div className="flex flex-col gap-1.5">
      <div className="text-[11.5px] font-medium text-muted">{label}</div>
      {url ? (
        <button
          type="button"
          onClick={() => onOpen(url, label)}
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
        </button>
      ) : (
        <div className="flex h-24 w-full items-center justify-center rounded-md border border-dashed border-border-strong text-[11px] text-faint">
          {notUploaded}
        </div>
      )}
    </div>
  );
}

/** Full-size document preview shown IN-PAGE (no new tab). Dismisses on backdrop click, the ✕
 *  button, or Esc. A broken/expired URL degrades to an "open in a new tab" link as a last resort.
 *  Sits above the guard-detail modal (z-[100]). */
function DocLightbox({
  url,
  label,
  openLabel,
  closeLabel,
  onClose,
}: {
  url: string;
  label: string;
  openLabel: string;
  closeLabel: string;
  onClose: () => void;
}) {
  const [imgError, setImgError] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={label}
      onClick={onClose}
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/75 p-4"
    >
      <button
        type="button"
        onClick={onClose}
        aria-label={closeLabel}
        className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-white/15 text-lg text-white transition hover:bg-white/25"
      >
        ✕
      </button>
      {imgError ? (
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          onClick={(e) => e.stopPropagation()}
          className="text-sm font-medium text-white underline"
        >
          {openLabel}
        </a>
      ) : (
        <figure onClick={(e) => e.stopPropagation()} className="flex flex-col items-center gap-2">
          {/* eslint-disable-next-line @next/next/no-img-element -- presigned S3 URL, not a static asset */}
          <img
            src={url}
            alt={label}
            onError={() => setImgError(true)}
            className="max-h-[85vh] max-w-[90vw] rounded object-contain shadow-2xl"
          />
          <figcaption className="text-xs text-white/80">{label}</figcaption>
        </figure>
      )}
    </div>
  );
}
