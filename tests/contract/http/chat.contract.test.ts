// Provider verification — chat service via the api-gateway (:3000 /v1).
//
// IMPORTANT: chat is NOT in the default e2e SERVICES list (the happy-path web e2e skips it), so the
// contract stack-up (tests/contract/stack-up.sh) brings the chat container up explicitly on top of
// e2e-stack-up.sh. With chat up, the gateway routes /v1/conversations + /v1/attachments to it.
// Message SEND is WS-only (no REST POST messages), so this file covers the REST surface: conversation
// create/list, message list, read receipt, attachment upload, plus auth (edge 401) and IDOR (403).
import { describe, expect, it } from "vitest";

import { CUSTOMER, GUARD } from "../src/accounts.js";
import { accessToken, bearer, gatewayUrl, http, tinyJpeg } from "../src/http.js";
import { assertResponseMatchesSpec } from "../src/validate.js";

// Seed conversation #1: participants = the test customer + pool guard #1 (NOT the test guard).
const SEED_CONVERSATION_ID = "22222222-0000-0000-0000-000000000001";

describe("chat contract (gateway /v1)", () => {
  it("POST /conversations (find-then-create) returns a contract-shaped ConversationResponse", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/conversations"), {
      method: "POST",
      headers: { ...bearer(token), "content-type": "application/json" },
      body: JSON.stringify({
        // request_id is a bare uuid (no cross-service FK); caller must be a participant.
        request_id: "dddddddd-0000-0000-0000-000000000001",
        participants: [
          { user_id: CUSTOMER.userId, role: "customer", display_name: "Contract Customer" },
          { user_id: GUARD.userId, role: "guard", display_name: "Contract Guard" },
        ],
      }),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("chat", "post", "/conversations", res);
  });

  it("GET /conversations returns the caller's enriched conversation list (contract-shaped)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl("/conversations"), { headers: bearer(token) });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("chat", "get", "/conversations", res);
  });

  it("GET /conversations/{id}/messages returns a contract-shaped message list", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl(`/conversations/${SEED_CONVERSATION_ID}/messages`), {
      headers: bearer(token),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("chat", "get", "/conversations/{id}/messages", res);
  });

  it("PUT /conversations/{id}/read is an idempotent receipt upsert (contract-shaped Empty)", async () => {
    const token = await accessToken(CUSTOMER);
    const res = await http(gatewayUrl(`/conversations/${SEED_CONVERSATION_ID}/read`), {
      method: "PUT",
      headers: bearer(token),
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("chat", "put", "/conversations/{id}/read", res);
    // The contract's Empty schema has no `required`, so the schema check alone only proves "an
    // object"; pin the documented `success: true` explicitly (code-review nit).
    expect((res.body as { success?: boolean }).success).toBe(true);
  });

  it("GET /conversations without a token → 401 at the edge", async () => {
    const res = await http(gatewayUrl("/conversations"));
    expect(res.status).toBe(401);
  });

  it("GET messages as a NON-participant → 403 (IDOR-gated, service ErrorBody)", async () => {
    // The test guard (0810000001) is NOT a participant of seed conversation #1 (that's pool guard #1).
    const token = await accessToken(GUARD);
    const res = await http(gatewayUrl(`/conversations/${SEED_CONVERSATION_ID}/messages`), {
      headers: bearer(token),
    });
    expect(res.status).toBe(403);
    await assertResponseMatchesSpec("chat", "get", "/conversations/{id}/messages", res);
  });

  it("POST /attachments (multipart, participant, writable conversation) returns a contract-shaped Attachment", async () => {
    const token = await accessToken(CUSTOMER);
    const fd = new FormData();
    fd.append("conversation_id", SEED_CONVERSATION_ID);
    fd.append("file", new Blob([tinyJpeg()], { type: "image/jpeg" }), "attach.jpg");
    const res = await http(gatewayUrl("/attachments"), {
      method: "POST",
      headers: bearer(token), // no content-type — fetch sets the multipart boundary
      body: fd,
    });
    expect(res.status).toBe(200);
    await assertResponseMatchesSpec("chat", "post", "/attachments", res);
  });
});
