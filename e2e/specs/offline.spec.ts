import { expect, test, type Page } from "@playwright/test";
import { input, openPage, openPalette, option, search } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

const disconnect = async (page: Page) => {
  await page.evaluate(() => (window as unknown as { liveSocket: { disconnect(): void } }).liveSocket.disconnect());
  await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(0);
};

const connect = async (page: Page) => {
  await page.evaluate(() => (window as unknown as { liveSocket: { connect(): void } }).liveSocket.connect());
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
};

test("a search while the LiveView is disconnected says so, and runs on reconnect", async ({ page }) => {
  await openPalette(page);
  await disconnect(page);
  await input(page).fill("the login");
  await expect(page.locator(".jumon-status", { hasText: "Not connected" })).toBeVisible();
  await expect(page.locator(".jumon-status-loading")).toHaveCount(0);

  await connect(page);
  await expect(option(page, "The login form forgets the email")).toBeVisible();
  await expect(page.locator(".jumon-status", { hasText: "Not connected" })).toHaveCount(0);
});

test("an action on the server while the LiveView is disconnected says so, and the palette stays open", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("the login");
  await expect(option(page, "The login form forgets the email")).toBeVisible();
  await disconnect(page);
  // Issues answered and keeps its results; People and Guides, which answer
  // in a task, had no reply yet.
  await expect(option(page, "The login form forgets the email")).toBeVisible();
  await expect(page.locator(".jumon-status", { hasText: "Not connected" })).toHaveCount(2);

  // "Close the issue", the second action of the result, runs on the server.
  await page.keyboard.press("ArrowRight");
  await expect(page.locator(".jumon-menu-item")).toHaveText([/Copy the key/, /Close the issue/, /Open in a new tab/, /Copy link/]);
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-message")).toContainText("Not connected");
  await expect(page.locator(".jumon-dialog")).toBeVisible();
  await expect(page.locator(".jumon-busy")).toHaveCount(0);
});

test("an action that pushes an event says so too, and the message goes on reconnect", async ({ page }) => {
  await openPalette(page);
  await disconnect(page);
  await search(page, "new issue", "New issue");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-message")).toContainText("Not connected");
  await expect(page.locator(".jumon-dialog")).toBeVisible();

  await connect(page);
  await expect(page.locator(".jumon-message")).toBeHidden();
});

test("a result in the list runs after a reconnection: the palette searches again", async ({ page }) => {
  // A new issue of this test, which its action closes.
  await openPalette(page);
  await search(page, "new issue", "New issue");
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toContainText("Created");
  const key = (await page.locator("#flash").textContent())!.replace("Created ", "");

  await openPalette(page);
  await input(page).fill(key);
  const result = page.locator(".jumon-list [role=option]", { hasText: key });
  await expect(result).toBeVisible();
  // Every source answered: none is waiting for the connection.
  await expect(page.locator(".jumon-busy")).toHaveCount(0, { timeout: 5000 });
  // The LiveView of the new connection is a new process: it knows only the
  // results of its own searches.
  await disconnect(page);
  await connect(page);
  await expect(page.locator(".jumon-busy")).toHaveCount(0);
  await result.hover();
  await page.keyboard.press("ArrowRight");
  await expect(page.locator(".jumon-menu-item").nth(1)).toHaveText(/Close the issue/);
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toHaveText(`Closed ${key}`);
});
