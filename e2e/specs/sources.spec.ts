import { expect, test } from "@playwright/test";
import { input, openPage, openPalette, option, search } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("a source answers in the reply of the search", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("the login");
  await expect(page.locator(".jumon-heading", { hasText: "Issues" })).toBeVisible();
  await expect(option(page, "The login form forgets the email")).toBeVisible();
});

test("a slow source shows that it is loading, then its results under its heading", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("shortc");
  await expect(option(page, "Keyboard shortcuts")).toBeVisible();
  // Guides answers after a second; meanwhile its heading says it is loading.
  await expect(page.locator(".jumon-status-loading").first()).toBeVisible();
  await expect(page.locator(".jumon-heading", { hasText: "Guides" })).toBeVisible();
  await expect(option(page, "Shortcuts")).toBeVisible({ timeout: 5000 });
  await expect(page.locator(".jumon-status-loading")).toHaveCount(0);
});

test("a result has actions of its own, with →", async ({ page }) => {
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
  await result.hover();
  await page.keyboard.press("ArrowRight");
  await expect(page.locator(".jumon-menu")).toBeVisible();
  await expect(page.locator(".jumon-menu-item")).toHaveText([/Copy the key/, /Close the issue/, /Open in a new tab/, /Copy link/]);
  // "Close the issue" runs on the server, as a result's action it was offered.
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-dialog")).toBeHidden();
  await expect(page.locator("#flash")).toHaveText(`Closed ${key}`);
});

test("an older query never replaces a newer one", async ({ page }) => {
  await openPalette(page);
  await input(page).pressSequentially("grace", { delay: 40 });
  await expect(option(page, "Grace Hopper")).toBeVisible();
  await input(page).fill("alan");
  await expect(option(page, "Alan Turing")).toBeVisible();
  await page.waitForTimeout(800);
  await expect(option(page, "Grace Hopper")).toHaveCount(0);
});
