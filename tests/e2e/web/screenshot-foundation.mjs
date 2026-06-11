// One-shot screenshot capture for the design-foundation PR (DoD: compare dashboard +
// login + a list page against the hi-fi mockups). NOT a test — run manually:
//   node web/screenshot-foundation.mjs <base-url> <out-dir> [mockup-dir]
// mockup-dir (the local redesign-pguard/project/pguard) is optional; when given, the
// matching mockup HTMLs are captured too for side-by-side comparison.
import { chromium } from "@playwright/test";

const [base = "http://localhost:3100", out = "/tmp/design-foundation-shots", mockups] =
  process.argv.slice(2);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

async function shot(url, name, { theme } = {}) {
  await page.goto(url, { waitUntil: "networkidle" });
  if (theme === "dark") {
    await page.evaluate(() => document.documentElement.setAttribute("data-theme", "dark"));
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(700); // fonts settle
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: false });
  console.log(`✓ ${name}.png`);
}

await shot(`${base}/preview/shell`, "app-shell-light");
await shot(`${base}/preview/shell`, "app-shell-dark", { theme: "dark" });
await shot(`${base}/login`, "app-login");

if (mockups) {
  const enc = (f) => `file://${encodeURI(`${mockups}/${f}`)}`;
  await shot(enc("Admin - Dashboard.html"), "mock-dashboard");
  await shot(enc("Admin - Login.html"), "mock-login");
  await shot(enc("Admin - Guards.html"), "mock-guards");
}

await browser.close();
