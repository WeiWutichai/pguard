// Loads the source-of-truth contracts and turns them into validatable JSON Schemas.
//
// These specs are OpenAPI 3.1 / AsyncAPI 3.0, but several were authored with the OpenAPI-3.0
// `nullable: true` keyword (which JSON Schema 2020-12 / Ajv does NOT understand). We dereference
// all $refs, then normalize `nullable: true` into a real 2020-12 nullable type so Ajv validates
// the schema the way the spec author intended — NOT against a hand-copied schema. This is what
// keeps the suite honest: we compare live responses to the actual committed contract, not to a
// duplicate that could silently drift from it.
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import $RefParser from "@apidevtools/json-schema-ref-parser";

const HERE = dirname(fileURLToPath(import.meta.url));
// tests/contract/src -> repo root
export const REPO_ROOT = resolve(HERE, "..", "..", "..");
const OPENAPI_DIR = resolve(REPO_ROOT, "contracts", "openapi");
const ASYNCAPI = resolve(REPO_ROOT, "contracts", "asyncapi", "events.yaml");

export type ServiceKey = "identity" | "booking" | "rating" | "chat";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

/**
 * Recursively rewrite OpenAPI-3.0-style `nullable: true` into JSON-Schema-2020-12 nullability.
 * Mutates in place (the input is a throwaway dereferenced copy).
 */
function normalizeNullable(node: Json): Json {
  if (Array.isArray(node)) {
    for (const el of node) normalizeNullable(el);
    return node;
  }
  if (node && typeof node === "object") {
    for (const key of Object.keys(node)) normalizeNullable(node[key]);

    if (node.nullable === true) {
      delete node.nullable;
      if (typeof node.type === "string") {
        node.type = [node.type, "null"];
      } else if (Array.isArray(node.type)) {
        if (!node.type.includes("null")) node.type.push("null");
      } else {
        // No direct `type` (e.g. a $ref-derived allOf, or an enum-only schema): express
        // nullability via anyOf so any underlying shape OR null validates.
        const inner: Json = {};
        for (const key of Object.keys(node)) {
          inner[key] = node[key];
          delete node[key];
        }
        node.anyOf = [inner, { type: "null" }];
      }
      // An enum alongside a now-nullable type must also admit null as a member.
      if (Array.isArray(node.enum) && !node.enum.includes(null)) node.enum.push(null);
    } else if (node.nullable === false) {
      delete node.nullable;
    }
  }
  return node;
}

const openapiCache = new Map<ServiceKey, Json>();

/** Dereferenced + nullable-normalized OpenAPI document for a service (cached). */
export async function loadOpenApi(service: ServiceKey): Promise<Json> {
  const cached = openapiCache.get(service);
  if (cached) return cached;
  const file = resolve(OPENAPI_DIR, `${service}.yaml`);
  const deref = await $RefParser.dereference(file);
  const normalized = normalizeNullable(structuredClone(deref));
  openapiCache.set(service, normalized);
  return normalized;
}

let asyncapiCache: Json | undefined;

/** Dereferenced + nullable-normalized AsyncAPI events document (cached). */
export async function loadAsyncApi(): Promise<Json> {
  if (asyncapiCache) return asyncapiCache;
  const deref = await $RefParser.dereference(ASYNCAPI);
  asyncapiCache = normalizeNullable(structuredClone(deref));
  return asyncapiCache;
}

export interface OperationContract {
  /** The OpenAPI Operation Object (operationId, security, responses, …). */
  operation: Json;
  /** The Responses Object keyed by status string. */
  responses: Json;
  /** `security` array if declared on the operation (undefined ⇒ inherits root / none). */
  security: Json[] | undefined;
}

/**
 * Look up an operation by its path template (AS WRITTEN in the spec, e.g. `/bookings/{id}`) and
 * HTTP method. Throws a descriptive error if the path/method is not in the contract — which is
 * itself a meaningful failure (a test targeting an undocumented route).
 */
export async function getOperation(
  service: ServiceKey,
  method: string,
  pathTemplate: string,
): Promise<OperationContract> {
  const doc = await loadOpenApi(service);
  const pathItem = doc.paths?.[pathTemplate];
  if (!pathItem) {
    const known = Object.keys(doc.paths ?? {}).join(", ");
    throw new Error(
      `Contract ${service}: path "${pathTemplate}" is not documented. Known paths: ${known}`,
    );
  }
  const operation = pathItem[method.toLowerCase()];
  if (!operation) {
    const verbs = Object.keys(pathItem)
      .filter((k) => ["get", "post", "put", "patch", "delete", "head", "options"].includes(k))
      .join(", ");
    throw new Error(
      `Contract ${service}: ${method.toUpperCase()} "${pathTemplate}" is not documented (have: ${verbs}).`,
    );
  }
  return {
    operation,
    responses: operation.responses ?? {},
    security: operation.security as Json[] | undefined,
  };
}

/** The JSON-body response schema documented for a given status, or undefined if none/no body. */
export function responseSchema(contract: OperationContract, status: number): Json | undefined {
  const resp = contract.responses[String(status)];
  if (!resp) return undefined;
  return resp.content?.["application/json"]?.schema;
}

/** True if a response status is documented at all for the operation. */
export function statusIsDocumented(contract: OperationContract, status: number): boolean {
  return Boolean(contract.responses[String(status)]);
}
