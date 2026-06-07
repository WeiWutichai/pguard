import { ApiGapPage } from "@/components/api-gap-page";

// v2 computes the price server-side at charge time (payment `expected_total` =
// base_fee × hours × guards + tip); there is no admin-managed service-rate catalog/CRUD in the
// booking contract. Documented gap until a pricing-catalog API is added.
export default function PricingPage() {
  return (
    <ApiGapPage
      titleKey="nav.pricing"
      reasonKey="gap.pricing"
      endpoints={[
        "GET /v1/pricing/services (booking — not implemented)",
        "POST/PUT/DELETE /v1/admin/pricing/services (booking — not implemented)",
      ]}
    />
  );
}
