//! `#[cfg(test)]` Redis test doubles for the edge auth / rate-limit layers.
//!
//! These let the **reconnect / fail-posture** behaviour be tested HERMETICALLY (no real Redis):
//! a [`FlakyRedis`] errors on its first `fail_first` commands (an outage) and then starts
//! replying (Redis "came back"), so a test can assert "errors while down, the NEXT request
//! self-heals" for both the fail-CLOSED auth layer and the fail-OPEN rate-limit layer.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

/// A [`redis::aio::ConnectionLike`] double. The first `fail_first` commands return an
/// `IoError` (the kind a dropped connection yields); every command after that returns
/// `Value::Int(success_value)`. `success_value` shapes the post-recovery reply — e.g. an
/// `exists`/`get` reads as `0`/not-revoked, while a rate-limit `INCR` returning a large value
/// re-enforces the limit (proving the layer queried Redis again rather than staying fail-open).
///
/// Cloneable + shares the call counter (like a real multiplexed/managed connection), so cloning
/// it into a handler doesn't reset the simulated outage.
#[derive(Clone)]
pub struct FlakyRedis {
    calls: Arc<AtomicUsize>,
    fail_first: usize,
    success_value: i64,
}

impl FlakyRedis {
    /// `fail_first` commands error (the outage), then every reply is `Int(success_value)`.
    pub fn new(fail_first: usize, success_value: i64) -> Self {
        Self {
            calls: Arc::new(AtomicUsize::new(0)),
            fail_first,
            success_value,
        }
    }

    /// A connection that never recovers during the test (every command errors).
    pub fn always_broken() -> Self {
        Self::new(usize::MAX, 0)
    }

    fn next_is_failure(&self) -> bool {
        self.calls.fetch_add(1, Ordering::SeqCst) < self.fail_first
    }
}

impl redis::aio::ConnectionLike for FlakyRedis {
    fn req_packed_command<'a>(
        &'a mut self,
        _cmd: &'a redis::Cmd,
    ) -> redis::RedisFuture<'a, redis::Value> {
        let fail = self.next_is_failure();
        let v = self.success_value;
        Box::pin(async move {
            if fail {
                Err(redis::RedisError::from((
                    redis::ErrorKind::IoError,
                    "simulated redis outage",
                )))
            } else {
                Ok(redis::Value::Int(v))
            }
        })
    }

    fn req_packed_commands<'a>(
        &'a mut self,
        _cmd: &'a redis::Pipeline,
        _offset: usize,
        _count: usize,
    ) -> redis::RedisFuture<'a, Vec<redis::Value>> {
        let fail = self.next_is_failure();
        let v = self.success_value;
        Box::pin(async move {
            if fail {
                Err(redis::RedisError::from((
                    redis::ErrorKind::IoError,
                    "simulated redis outage",
                )))
            } else {
                Ok(vec![redis::Value::Int(v)])
            }
        })
    }

    fn get_db(&self) -> i64 {
        0
    }
}
