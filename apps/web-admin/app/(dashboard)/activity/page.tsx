import { ApiGapPage } from "@/components/api-gap-page";

// v2 has no admin activity/audit-log feed endpoint. The only timestamped admin-readable stream is
// reviews (already on /reviews); a cross-service activity log needs a dedicated backend endpoint.
// Documented gap (same pattern as slice 2) rather than a misleading reviews-only "activity log".
// Lead = the hi-fi mockup's topbar subtitle (Activity_Log.md).
export default function ActivityPage() {
  return (
    <ApiGapPage
      titleKey="nav.activity"
      reasonKey="gap.activity"
      lead={{ th: "บันทึกการตรวจสอบระบบ", en: "System audit trail" }}
      endpoints={["GET /v1/admin/activity (audit/activity feed — not implemented)"]}
    />
  );
}
