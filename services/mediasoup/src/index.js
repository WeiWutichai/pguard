// Entry point — load config (fail-fast → exit 1) then start the control plane.

import { loadConfig } from './config.js';
import { start } from './server.js';

let config;
try {
  config = loadConfig();
} catch (e) {
  console.error(`[mediasoup] config error: ${e.message}`);
  process.exit(1);
}

start(config).catch((e) => {
  console.error(`[mediasoup] failed to start: ${e.message}`);
  process.exit(1);
});
