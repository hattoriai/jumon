import { expect, test } from "@playwright/test";
import { input, names, openPage, openPalette, search } from "./support";

test("a page without LiveView has the actions the browser does alone", async ({ page }) => {
  await openPage(page, "/plain");
  await openPalette(page);
  const all = await names(page);
  expect(all).toContain("People");
  expect(all).not.toContain("New issue");
  expect(all).not.toContain("Assign to…");
  await input(page).fill("the");
  await page.waitForTimeout(400);
  await expect(page.locator(".jumon-heading", { hasText: "Guides" })).toHaveCount(0);
  await search(page, "people", "People");
  await page.keyboard.press("Enter");
  await expect(page.locator("#people-title")).toBeVisible();
});

test("a link with a method is sent as a form with the CSRF token", async ({ page }) => {
  await openPage(page, "/");
  await openPalette(page);
  await search(page, "sign out", "Sign out");
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toHaveText("Signed out (not really)");
});
