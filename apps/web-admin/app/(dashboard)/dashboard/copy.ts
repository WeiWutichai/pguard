// Screen-local bilingual copy for the dashboard rebuild — design strings quoted EXACTLY
// from the hi-fi mockup spec. Keys that already exist in src/lib/i18n with the same copy
// (dashboard.title, dashboard.card.onlineGuards, dashboard.card.*, dashboard.chart.*,
// dashboard.gap.bookings, common.*) are used via t() instead; i18n.tsx is single-writer,
// so NEW design copy lives here.
export const COPY = {
  th: {
    subtitle: "ภาพรวมการดำเนินงานวันนี้",
    kpiActiveJobs: "งานที่กำลังดำเนิน",
    kpiRevenueToday: "รายได้วันนี้",
    kpiPendingApprovals: "รออนุมัติ",
    // Honest gap chip — these design cells/panels have no v2 admin endpoint yet.
    awaitingApi: "รอ API",
    noAdminEndpoint: "ยังไม่มี endpoint สำหรับแอดมินใน v2",
    mapTitle: "แผนที่สด",
    online: "ออนไลน์",
    openFull: "เปิดเต็มจอ →",
    mapEmpty: "ไม่มีเจ้าหน้าที่ออนไลน์",
    alertsTitle: "แจ้งเตือน",
    alertsGap:
      "ต้องมี endpoint การแจ้งเตือนสำหรับแอดมิน (เช็คอินที่ขาด · คิวคืนเงิน · ผู้สมัครใหม่)",
    revenueTitle: "รายได้ 7 วันล่าสุด",
    feedTitle: "กิจกรรมล่าสุด",
    feedGap: "ต้องมี endpoint ฟีดกิจกรรมสำหรับแอดมิน",
  },
  en: {
    subtitle: "Today's operations overview",
    kpiActiveJobs: "Active jobs",
    kpiRevenueToday: "Revenue today",
    kpiPendingApprovals: "Pending approvals",
    awaitingApi: "Awaiting API",
    noAdminEndpoint: "No v2 admin endpoint yet",
    mapTitle: "Live map",
    online: "online",
    openFull: "Open full →",
    mapEmpty: "No guards online",
    alertsTitle: "Alerts",
    alertsGap:
      "Needs an admin alerts endpoint (missed check-ins · refund queue · new applicants)",
    revenueTitle: "Revenue, last 7 days",
    feedTitle: "Recent activity",
    feedGap: "Needs an admin activity-feed endpoint",
  },
} as const;
