import { notFound } from "next/navigation";

import { ShellPreview } from "./preview-client";

/**
 * DEV-ONLY visual checkpoint for the design foundation: renders the new shell + the full
 * ui/ component set with sample data, with no auth/backend needed — used to screenshot
 * against the hi-fi mockups (Admin - Dashboard.html). 404s in production builds, so it
 * adds no surface to the deployed admin.
 */
export default function Page() {
  if (process.env.NODE_ENV === "production") notFound();
  return <ShellPreview />;
}
