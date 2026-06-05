// SFU engine — the WebRTC media plane. The `mediasoup` native package is an
// optionalDependency + dynamically imported so the control/auth layer (and its tests +
// `npm ci`) work without the native build; in production the package MUST be installed.
//
// A single worker + router is sufficient for the 2-party calls v2 needs; transports/
// producers/consumers hang off the router (created on demand by the control endpoints).

let workerPromise = null;
let router = null;

/** Lazily import mediasoup; throws a clear error if the optional native dep is absent. */
async function loadMediasoup() {
  try {
    return await import('mediasoup');
  } catch {
    throw new Error(
      'mediasoup native engine not installed — run `npm install mediasoup` (it is an ' +
        'optionalDependency; required for the media plane in production)',
    );
  }
}

/**
 * Get (or lazily create) the shared media router. Worker RTC ports are confined to the
 * configured UDP range; the announced IP is what peers see in ICE candidates.
 * @param {{announcedIp: string, rtcMinPort: number, rtcMaxPort: number}} config
 */
export async function getRouter(config) {
  if (router) return router;
  if (!workerPromise) {
    workerPromise = (async () => {
      const mediasoup = await loadMediasoup();
      const worker = await mediasoup.createWorker({
        rtcMinPort: config.rtcMinPort,
        rtcMaxPort: config.rtcMaxPort,
      });
      worker.on('died', () => {
        // A dead worker is unrecoverable in-process; exit so the orchestrator restarts us.
        console.error('[mediasoup] worker died; exiting');
        process.exit(1);
      });
      router = await worker.createRouter({
        mediaCodecs: [
          { kind: 'audio', mimeType: 'audio/opus', clockRate: 48000, channels: 2 },
          { kind: 'video', mimeType: 'video/VP8', clockRate: 90000 },
        ],
      });
      return router;
    })();
  }
  await workerPromise;
  return router;
}

/** Whether the optional native engine is importable (used to report capability, not gate auth). */
export async function sfuAvailable() {
  try {
    await loadMediasoup();
    return true;
  } catch {
    return false;
  }
}
