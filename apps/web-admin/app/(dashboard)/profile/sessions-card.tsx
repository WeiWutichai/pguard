"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, LogOut, Monitor, Smartphone } from "lucide-react";

import type { components } from "@/api/generated/identity";
import { identityApi } from "@/lib/api";
import type { Lang } from "@/lib/lang";
import { Badge, Button, Modal, Panel, PanelBody, PanelHead } from "@/components/ui";

import type { ProfileCopy } from "./copy";

type SessionView = components["schemas"]["SessionView"];

/**
 * Per-device session list (#144). LIVE against identity:
 *   GET    /auth/sessions               → SessionView[]  (`current` marks this browser; `ip` masked)
 *   DELETE /auth/sessions/{family_id}   → sign out one device (own-only)
 *   POST   /auth/revoke-all             → sign out everywhere (incl. this device → bounce to /login)
 */
export function SessionsCard({ c, lang }: { c: ProfileCopy; lang: Lang }) {
  const router = useRouter();
  const [sessions, setSessions] = useState<SessionView[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);

  const load = useCallback((alive: () => boolean) => {
    return identityApi
      .GET("/auth/sessions", {})
      .then(({ data, error }) => {
        if (!alive()) return;
        setLoadError(Boolean(error));
        setSessions(error ? [] : (data?.data ?? []));
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setLoadError(true);
        setLoading(false);
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void load(() => alive);
    return () => {
      alive = false;
    };
  }, [load]);

  // ---- revoke ALL (sign out everywhere) ----
  const [allOpen, setAllOpen] = useState(false);
  const [allBusy, setAllBusy] = useState(false);
  const [allError, setAllError] = useState(false);

  async function signOutEverywhere() {
    setAllBusy(true);
    setAllError(false);
    const res = await identityApi.POST("/auth/revoke-all", {});
    if (res.error) {
      setAllBusy(false);
      setAllError(true);
      return;
    }
    router.replace("/login");
    router.refresh();
  }

  // ---- revoke ONE device ----
  const [revokeTarget, setRevokeTarget] = useState<SessionView | null>(null);
  const [revokeBusy, setRevokeBusy] = useState(false);
  const [revokeError, setRevokeError] = useState(false);

  async function revokeOne() {
    if (!revokeTarget) return;
    setRevokeBusy(true);
    setRevokeError(false);
    const res = await identityApi.DELETE("/auth/sessions/{family_id}", {
      params: { path: { family_id: revokeTarget.family_id } },
    });
    setRevokeBusy(false);
    if (res.error) {
      setRevokeError(true);
      return;
    }
    // Revoking THIS device ends our own session → back to login; otherwise just drop the row.
    if (revokeTarget.current) {
      router.replace("/login");
      router.refresh();
      return;
    }
    setSessions((prev) => prev.filter((s) => s.family_id !== revokeTarget.family_id));
    setRevokeTarget(null);
  }

  const fmt = (iso?: string | null) =>
    iso
      ? new Date(iso).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
          month: "short",
          day: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        })
      : "—";

  const isMobile = (ua?: string | null) => Boolean(ua && /mobile|android|iphone|ipad/i.test(ua));

  return (
    <Panel>
      <PanelHead title={c.sessionsHead} sub={c.sessionsSub}>
        <Button variant="danger-ghost" size="sm" onClick={() => setAllOpen(true)}>
          <LogOut size={15} />
          {c.signOutAll}
        </Button>
      </PanelHead>
      <PanelBody className="py-1">
        {loading ? (
          <div className="flex items-center gap-2 py-4 text-[12.5px] text-muted">
            <Loader2 className="size-4 animate-spin" />
            {c.sessionsLoading}
          </div>
        ) : loadError ? (
          <p className="py-4 text-[12.5px] text-danger" role="alert">
            {c.sessionsError}
          </p>
        ) : sessions.length === 0 ? (
          <p className="py-4 text-[12.5px] text-muted">{c.sessionsEmpty}</p>
        ) : (
          <ul className="divide-y divide-border">
            {sessions.map((s) => (
              <li key={s.family_id} className="flex items-center gap-3 py-3">
                <span className="flex size-9 flex-none items-center justify-center rounded-full bg-sunken text-muted">
                  {isMobile(s.user_agent) ? <Smartphone size={17} /> : <Monitor size={17} />}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="truncate text-[13px] font-medium text-text-strong">
                      {s.user_agent || c.unknownDevice}
                    </span>
                    {s.current && <Badge tone="green">{c.thisDevice}</Badge>}
                  </div>
                  <div className="mt-0.5 flex flex-wrap gap-x-3 text-[11.5px] text-muted">
                    {s.ip ? <span className="font-mono">{s.ip}</span> : null}
                    <span>
                      {c.lastSeen}: {fmt(s.last_used_at ?? s.created_at)}
                    </span>
                  </div>
                </div>
                <Button
                  variant="danger-ghost"
                  size="sm"
                  className="flex-none"
                  onClick={() => {
                    setRevokeError(false);
                    setRevokeTarget(s);
                  }}
                >
                  {c.revokeSession}
                </Button>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-1 mb-1 pt-2 text-[12px] text-muted">{c.signOutAllSub}</p>
        {allError && (
          <p role="alert" className="mb-2 text-sm text-danger">
            {c.sessionsError}
          </p>
        )}
      </PanelBody>

      {/* revoke ALL confirm */}
      <Modal open={allOpen} onClose={() => setAllOpen(false)} title={c.signOutConfirmTitle}>
        <p className="text-sm text-muted">{c.signOutConfirmBody}</p>
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setAllOpen(false)} disabled={allBusy}>
            {c.cancel}
          </Button>
          <Button variant="danger-ghost" onClick={signOutEverywhere} disabled={allBusy}>
            <LogOut size={15} />
            {c.confirm}
          </Button>
        </div>
      </Modal>

      {/* revoke ONE confirm */}
      <Modal
        open={revokeTarget !== null}
        onClose={() => setRevokeTarget(null)}
        title={c.revokeSessionTitle}
      >
        <p className="text-sm text-muted">{c.revokeSessionBody}</p>
        {revokeTarget?.user_agent ? (
          <p className="mt-2 truncate font-mono text-[12px] text-faint">{revokeTarget.user_agent}</p>
        ) : null}
        {revokeError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {c.revokeSessionError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setRevokeTarget(null)} disabled={revokeBusy}>
            {c.cancel}
          </Button>
          <Button variant="danger-ghost" onClick={revokeOne} disabled={revokeBusy}>
            {revokeBusy ? <Loader2 className="size-4 animate-spin" /> : <LogOut size={15} />}
            {c.revokeSession}
          </Button>
        </div>
      </Modal>
    </Panel>
  );
}
