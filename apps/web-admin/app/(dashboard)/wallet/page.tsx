import { ApiGapPage } from "@/components/api-gap-page";

// v2 made refunds automatic/event-driven (the payment consumer finalizes proration + emits
// `payment.refund_processed` — "no admin step needed", per payment.yaml). There is no admin
// payments-bulk list, refunds list, or refund-process endpoint; `GET /payments` is
// customer-scoped ("the caller's payments"). Documented gap until an admin wallet API is added.
export default function WalletPage() {
  return (
    <ApiGapPage
      titleKey="nav.wallet"
      reasonKey="gap.wallet"
      endpoints={[
        "GET /v1/admin/payments (payment — not implemented; /payments is customer-scoped)",
        "GET /v1/admin/refunds?status= (payment — not implemented)",
        "PUT /v1/admin/refunds/{id}/process (payment — not implemented)",
      ]}
    />
  );
}
