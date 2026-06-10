// Ajv-backed validation of live responses + emitted events against the dereferenced contracts.
//
// Design notes that keep these tests meaningful (not tautologies):
//  - We validate against the schema EXTRACTED FROM THE COMMITTED CONTRACT (specs.ts), never a
//    re-typed copy. If a provider drops a required field or changes a type, Ajv fails here.
//  - strict:false so real-world OpenAPI keywords (example, discriminator, int64 format, …) don't
//    blow up the validator; ajv-formats covers uuid/date-time/email/uri.
//  - additionalProperties is NOT forced to false. OpenAPI does not imply it, and the event
//    envelope legitimately carries an extra `traceparent` field. So we catch missing/typed-wrong
//    fields (the drift that matters) while staying forward-compatible with added fields.
import Ajv2020, { type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import {
  getOperation,
  loadAsyncApi,
  responseSchema,
  statusIsDocumented,
  type ServiceKey,
} from "./specs.js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

let ajvSingleton: Ajv2020 | undefined;
function ajv(): Ajv2020 {
  if (!ajvSingleton) {
    ajvSingleton = new Ajv2020({ strict: false, allErrors: true, allowUnionTypes: true });
    addFormats(ajvSingleton);
  }
  return ajvSingleton;
}

function compile(schema: Json): ValidateFunction {
  return ajv().compile(schema);
}

function formatErrors(errors: ErrorObject[] | null | undefined): string {
  if (!errors || errors.length === 0) return "(no detail)";
  return errors
    .map((e) => `  • ${e.instancePath || "<root>"} ${e.message ?? ""} ${JSON.stringify(e.params)}`)
    .join("\n");
}

export interface ValidationResult {
  valid: boolean;
  message: string;
}

/** Validate arbitrary data against a JSON Schema; returns a structured result (never throws). */
export function validateSchema(schema: Json, data: unknown): ValidationResult {
  const validate = compile(schema);
  const valid = validate(data) as boolean;
  return {
    valid,
    message: valid ? "ok" : formatErrors(validate.errors),
  };
}

export interface LiveResponse {
  status: number;
  /** Parsed JSON body (or undefined if the response had no body). */
  body: unknown;
}

/**
 * Assert that a live response conforms to the service contract: the status must be a DOCUMENTED
 * response for that operation, and (if that response documents a JSON body) the body must validate
 * against the documented schema. Throws a descriptive Error on any mismatch — that Error is the
 * test failure.
 *
 * This is the core provider-verification primitive. It catches:
 *  - undocumented status codes (provider returns a status the contract never promised),
 *  - missing required fields, wrong types, bad formats, enum violations in the body.
 */
export async function assertResponseMatchesSpec(
  service: ServiceKey,
  method: string,
  pathTemplate: string,
  res: LiveResponse,
): Promise<void> {
  const contract = await getOperation(service, method, pathTemplate);
  if (!statusIsDocumented(contract, res.status)) {
    const documented = Object.keys(contract.responses).join(", ");
    throw new Error(
      `${service} ${method} ${pathTemplate}: response status ${res.status} is NOT documented in the contract ` +
        `(documented: ${documented}).\nBody: ${JSON.stringify(res.body)?.slice(0, 600)}`,
    );
  }
  const schema = responseSchema(contract, res.status);
  if (!schema) return; // documented response without a JSON body schema — nothing more to check.
  const result = validateSchema(schema, res.body);
  if (!result.valid) {
    throw new Error(
      `${service} ${method} ${pathTemplate} → ${res.status}: response body does NOT match the contract schema:\n` +
        `${result.message}\nBody: ${JSON.stringify(res.body)?.slice(0, 800)}`,
    );
  }
}

/**
 * Interpret an operation's `security` requirement: does the contract require a USER bearer token?
 * Returns true iff `security` is a non-empty array whose requirement objects reference `bearerAuth`.
 * `security: []` (explicitly public) or only `serviceAuth` ⇒ false. Used to derive auth-required
 * assertions FROM THE CONTRACT, so an intentional contract change moves the expectation with it,
 * while an unintended provider/contract divergence is caught.
 */
export async function requiresUserBearer(
  service: ServiceKey,
  method: string,
  pathTemplate: string,
): Promise<boolean> {
  const contract = await getOperation(service, method, pathTemplate);
  const security = contract.security;
  if (!Array.isArray(security) || security.length === 0) return false;
  return security.some((req) => req && Object.prototype.hasOwnProperty.call(req, "bearerAuth"));
}

/** The named EnvelopeOf_* schema from the AsyncAPI events contract. */
export async function eventSchema(schemaName: string): Promise<Json> {
  const doc = await loadAsyncApi();
  const schema = doc.components?.schemas?.[schemaName];
  if (!schema) {
    const known = Object.keys(doc.components?.schemas ?? {}).join(", ");
    throw new Error(`AsyncAPI: schema "${schemaName}" not found. Known: ${known}`);
  }
  return schema;
}

/**
 * Validate a full emitted EventEnvelope (read from a service outbox) against its AsyncAPI
 * EnvelopeOf_* schema — envelope fields (event_id, event_type, occurred_at, correlation_id) AND
 * the inner payload's required fields. Throws on mismatch.
 */
export async function assertEventMatchesSchema(
  schemaName: string,
  envelope: unknown,
): Promise<void> {
  const schema = await eventSchema(schemaName);
  const result = validateSchema(schema, envelope);
  if (!result.valid) {
    throw new Error(
      `Event does not match AsyncAPI ${schemaName}:\n${result.message}\n` +
        `Envelope: ${JSON.stringify(envelope)?.slice(0, 800)}`,
    );
  }
}
