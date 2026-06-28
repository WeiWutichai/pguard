"use client";

import { useCallback, useEffect, useState } from "react";
import { Copy, KeyRound, Loader2, Plus } from "lucide-react";

import type { components } from "@/api/generated/identity";
import { identityApi } from "@/lib/api";
import type { Lang } from "@/lib/lang";
import {
  Badge,
  Button,
  Field,
  Input,
  Modal,
  Panel,
  PanelBody,
  PanelHead,
  Table,
  Td,
  Th,
} from "@/components/ui";

import type { ProfileCopy } from "./copy";

type ApiTokenView = components["schemas"]["ApiTokenView"];
type CreatedToken = components["schemas"]["CreateApiTokenResponse"];

/**
 * Admin API tokens (#144). LIVE against identity (admin role; gateway routes `/admin/api-tokens`):
 *   GET    /admin/api-tokens        → ApiTokenView[]  (NEVER the secret)
 *   POST   /admin/api-tokens        → CreateApiTokenResponse  (full `token` shown ONCE)
 *   DELETE /admin/api-tokens/{id}   → revoke (own-only)
 */
export function ApiTokensCard({ c, lang }: { c: ProfileCopy; lang: Lang }) {
  const [tokens, setTokens] = useState<ApiTokenView[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);

  const load = useCallback((alive: () => boolean) => {
    return identityApi
      .GET("/admin/api-tokens", {})
      .then(({ data, error }) => {
        if (!alive()) return;
        setLoadError(Boolean(error));
        setTokens(error ? [] : (data?.data ?? []));
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

  // ---- create ----
  const [createOpen, setCreateOpen] = useState(false);
  const [tokenName, setTokenName] = useState("");
  const [nameErr, setNameErr] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  // ---- created-once reveal ----
  const [created, setCreated] = useState<CreatedToken | null>(null);
  const [copied, setCopied] = useState(false);

  function openCreate() {
    setTokenName("");
    setNameErr(null);
    setCreateError(null);
    setCreateOpen(true);
  }

  async function submitCreate() {
    setCreateError(null);
    const name = tokenName.trim();
    if (name.length === 0) {
      setNameErr(c.tokenNameRequired);
      return;
    }
    setCreating(true);
    const res = await identityApi.POST("/admin/api-tokens", { body: { name } });
    setCreating(false);
    if (res.error || !res.data?.data) {
      setCreateError(c.createTokenError);
      return;
    }
    setCreateOpen(false);
    setCreated(res.data.data);
    setCopied(false);
    // Optimistically add the new row (without the secret) so the list reflects it immediately.
    setTokens((prev) => [
      {
        id: res.data!.data!.id,
        name: res.data!.data!.name,
        prefix: res.data!.data!.prefix,
        role: "admin",
        created_at: new Date().toISOString(),
        last_used_at: null,
        revoked: false,
      },
      ...prev,
    ]);
  }

  async function copyToken() {
    if (!created) return;
    try {
      await navigator.clipboard.writeText(created.token);
      setCopied(true);
    } catch {
      /* clipboard blocked — token is still visible to copy by hand */
    }
  }

  // ---- revoke ----
  const [revokeTarget, setRevokeTarget] = useState<ApiTokenView | null>(null);
  const [revokeBusy, setRevokeBusy] = useState(false);
  const [revokeError, setRevokeError] = useState(false);

  async function revoke() {
    if (!revokeTarget) return;
    setRevokeBusy(true);
    setRevokeError(false);
    const res = await identityApi.DELETE("/admin/api-tokens/{id}", {
      params: { path: { id: revokeTarget.id } },
    });
    setRevokeBusy(false);
    if (res.error) {
      setRevokeError(true);
      return;
    }
    setTokens((prev) =>
      prev.map((t) => (t.id === revokeTarget.id ? { ...t, revoked: true } : t)),
    );
    setRevokeTarget(null);
  }

  const fmt = (iso?: string | null) =>
    iso
      ? new Date(iso).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
          year: "numeric",
          month: "short",
          day: "numeric",
        })
      : null;

  return (
    <Panel>
      <PanelHead title={c.tokensHead} sub={c.tokensSub}>
        <Button variant="secondary" size="sm" onClick={openCreate}>
          <Plus size={15} />
          {c.generate}
        </Button>
      </PanelHead>
      <PanelBody className="px-0 py-0">
        {loading ? (
          <div className="flex items-center gap-2 px-5 py-5 text-[12.5px] text-muted">
            <Loader2 className="size-4 animate-spin" />
            {c.tokensLoading}
          </div>
        ) : loadError ? (
          <p className="px-5 py-5 text-[12.5px] text-danger" role="alert">
            {c.tokensError}
          </p>
        ) : tokens.length === 0 ? (
          <p className="px-5 py-6 text-center text-[12.5px] text-muted">{c.tokensEmpty}</p>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{c.colName}</Th>
                <Th>{c.colPrefix}</Th>
                <Th>{c.colCreated}</Th>
                <Th>{c.colLastUsed}</Th>
                <Th>{c.colStatus}</Th>
                <Th className="text-right">{c.colActions}</Th>
              </tr>
            </thead>
            <tbody>
              {tokens.map((t) => (
                <tr key={t.id} className="last:[&>td]:border-b-0">
                  <Td className="font-medium text-text-strong">{t.name}</Td>
                  <Td className="font-mono text-[12.5px] text-muted">{t.prefix}…</Td>
                  <Td className="text-[12.5px] text-muted">{fmt(t.created_at) ?? "—"}</Td>
                  <Td className="text-[12.5px] text-muted">{fmt(t.last_used_at) ?? c.neverUsed}</Td>
                  <Td>
                    {t.revoked ? (
                      <Badge tone="red">{c.statusRevoked}</Badge>
                    ) : (
                      <Badge tone="green">{c.statusActive}</Badge>
                    )}
                  </Td>
                  <Td className="text-right">
                    {!t.revoked && (
                      <Button
                        variant="danger-ghost"
                        size="sm"
                        onClick={() => {
                          setRevokeError(false);
                          setRevokeTarget(t);
                        }}
                      >
                        {c.revoke}
                      </Button>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </PanelBody>

      {/* create */}
      <Modal open={createOpen} onClose={() => setCreateOpen(false)} title={c.createTokenTitle}>
        <p className="mb-4 text-sm text-muted">{c.createTokenIntro}</p>
        <Field label={c.tokenNameLabel} error={nameErr ?? undefined} className="mb-0">
          <Input
            value={tokenName}
            onChange={(e) => {
              setTokenName(e.target.value);
              setNameErr(null);
            }}
            placeholder={c.tokenNamePlaceholder}
            maxLength={120}
            error={Boolean(nameErr)}
            aria-label={c.tokenNameLabel}
          />
        </Field>
        {createError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {createError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setCreateOpen(false)} disabled={creating}>
            {c.cancel}
          </Button>
          <Button onClick={submitCreate} disabled={creating || tokenName.trim().length === 0}>
            {creating ? <Loader2 className="size-4 animate-spin" /> : <KeyRound size={15} />}
            {c.createTokenSubmit}
          </Button>
        </div>
      </Modal>

      {/* created-once reveal */}
      <Modal open={created !== null} onClose={() => setCreated(null)} title={c.tokenCreatedTitle}>
        <p className="mb-2 text-sm text-muted">{c.tokenCreatedIntro}</p>
        <div className="mb-3 flex items-start gap-2 rounded-lg border border-warning-bg bg-warning-bg px-4 py-3 text-[12.5px] text-amber-700 dark:text-amber-300">
          <Badge tone="amber">!</Badge>
          <span>{c.tokenCreatedWarn}</span>
        </div>
        <div className="flex items-stretch gap-2">
          <code className="min-w-0 flex-1 overflow-x-auto rounded-md border border-border bg-sunken px-3 py-2.5 font-mono text-[12.5px] text-text-strong">
            {created?.token}
          </code>
          <Button variant="secondary" onClick={copyToken} className="flex-none">
            <Copy size={15} />
            {copied ? c.tokenCopied : c.copy}
          </Button>
        </div>
        <div className="mt-5 flex justify-end">
          <Button onClick={() => setCreated(null)}>{c.done}</Button>
        </div>
      </Modal>

      {/* revoke confirm */}
      <Modal
        open={revokeTarget !== null}
        onClose={() => setRevokeTarget(null)}
        title={c.revokeTokenTitle}
      >
        <p className="text-sm text-muted">{c.revokeTokenBody}</p>
        {revokeTarget ? (
          <p className="mt-2 text-[13px] font-medium text-text-strong">
            {revokeTarget.name}{" "}
            <span className="font-mono text-faint">({revokeTarget.prefix}…)</span>
          </p>
        ) : null}
        {revokeError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {c.revokeTokenError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setRevokeTarget(null)} disabled={revokeBusy}>
            {c.cancel}
          </Button>
          <Button variant="danger-ghost" onClick={revoke} disabled={revokeBusy}>
            {revokeBusy ? <Loader2 className="size-4 animate-spin" /> : null}
            {c.revoke}
          </Button>
        </div>
      </Modal>
    </Panel>
  );
}
