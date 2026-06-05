// pguard v2 scaffold stub — health check Route Handler (GET /healthz).
// Mirrors the per-service healthz convention used across pguard services.
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({ status: "ok", app: "web-admin" });
}
