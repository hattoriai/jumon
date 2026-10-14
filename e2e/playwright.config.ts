import { defineConfig, devices } from "@playwright/test";

// The browser tests run against the development server (`mix dev`, see
// dev.exs). The web server command builds the bundle first, and starts
// the server without watchers or live reload. It has its own port (4098,
// or E2E_PORT), so that a `mix dev` with watchers on 4099 is never the
// server of a run.
const port = Number(process.env.E2E_PORT ?? 4098);
const baseURL = `http://127.0.0.1:${port}`;

// The three engines. E2E_BROWSERS picks some of them (comma-separated, for
// example "firefox" or "chromium,webkit"); the default is all three. CI
// runs one job for each.
const browsers = {
  chromium: devices["Desktop Chrome"],
  firefox: devices["Desktop Firefox"],
  webkit: devices["Desktop Safari"],
};
type Browser = keyof typeof browsers;

const picked = (process.env.E2E_BROWSERS ?? Object.keys(browsers).join(","))
  .split(",")
  .map((name) => name.trim())
  .filter((name) => name !== "");
for (const name of picked) {
  if (!(name in browsers)) throw new Error(`E2E_BROWSERS: unknown browser "${name}", use chromium, firefox or webkit`);
}

export default defineConfig({
  testDir: "./specs",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: "list",
  use: {
    baseURL,
    // The dev pages give no locale: the palette speaks English.
    locale: "en-GB",
    timezoneId: "Europe/Lisbon",
    // A failed test keeps its trace and a screenshot, in test-results/.
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: (picked as Browser[]).map((name) => ({ name, use: { ...browsers[name] } })),
  webServer: {
    command: "mix do jumon.build + dev",
    cwd: "..",
    url: `${baseURL}/`,
    env: { PORT: String(port), JUMON_DEV_WATCH: "false", MIX_ENV: "dev" },
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    stdout: "ignore",
    stderr: "pipe",
  },
});
