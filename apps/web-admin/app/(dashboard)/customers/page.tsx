import { ApiGapPage } from "@/components/api-gap-page";

// No admin customer-list endpoint exists in the v2 contracts (profile only exposes the self
// `POST /profile/customer` + `GET /profile/me`). Documented gap until the backend adds one.
export default function CustomersPage() {
  return (
    <ApiGapPage
      titleKey="nav.customers"
      reasonKey="gap.customers"
      endpoints={["GET /v1/admin/customer-profiles (profile — not implemented)"]}
    />
  );
}
