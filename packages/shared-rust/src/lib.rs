//! pguard shared library — types, errors, config, auth primitives.
//!
//! Ported and cleaned from v1 `services/shared` (`../guard-dispatch/services/shared`).
//! v2 additions: [`service_jwt`] for authenticated service-to-service calls (replaces
//! v1's unauthenticated `/internal/*` endpoints — see CLAUDE.md "Service auth").

pub mod auth;
pub mod config;
pub mod db;
pub mod error;
pub mod models;
pub mod redis_client;
pub mod service_jwt;
