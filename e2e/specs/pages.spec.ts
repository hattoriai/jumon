import { expect, test } from "@playwright/test";
import { active, input, names, openPage, openPalette, option, search } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("an action with children opens their page, and Backspace goes back", async ({ page }) => {
  await openPalette(page);
  await search(page, "theme", "Theme");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-crumb")).toHaveText(["Theme"]);
  await expect(input(page)).toHaveValue("");
  expect(await names(page)).toEqual(["Light", "Dark", "Sumi", "Sumi, dark"]);
  await page.keyboard.press("Backspace");
  await expect(page.locator(".jumon-crumbs")).toBeHidden();
  await expect(input(page)).toHaveValue("theme");
});

test("a child runs JS commands", async ({ page }) => {
  await openPalette(page);
  await search(page, "dark", "Dark");
  await expect(active(page).locator(".jumon-item-trail")).toHaveText("Theme › ");
  await page.keyboard.press("Enter");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
});

test("two thousand children: only the rows in view are drawn", async ({ page }) => {
  await openPalette(page);
  await search(page, "go to page", "Go to page…");
  await page.keyboard.press("Enter");
  await expect(option(page, "Page 1")).toBeVisible();
  expect(await page.locator(".jumon-list [role=option]").count()).toBeLessThan(60);
  await page.keyboard.press("PageDown");
  await page.keyboard.press("PageDown");
  await expect(active(page).locator(".jumon-item-name")).not.toHaveText("Page 1");
  await input(page).fill("1999");
  await expect(active(page).locator(".jumon-item-name")).toHaveText("Page 1999");
  await page.keyboard.press("Enter");
  await expect(page.locator("#page")).toHaveText("Page 1999");
});

test("Escape goes back a page, then closes", async ({ page }) => {
  await openPalette(page);
  await search(page, "theme", "Theme");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Escape");
  await expect(page.locator(".jumon-crumbs")).toBeHidden();
  await page.keyboard.press("Escape");
  await expect(page.locator(".jumon-dialog")).toBeHidden();
});

test("the actions of a page leave with it", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("close web");
  await expect(page.locator(".jumon-status-empty")).toBeVisible();
  await page.keyboard.press("Escape");
  await openPage(page, "/issues/3");
  await expect(page.locator("#issue-title")).toBeVisible();
  await openPalette(page);
  await search(page, "close web-3", "Close WEB-3");
  await expect(page.locator(".jumon-heading").first()).toHaveText("This issue");
  await page.keyboard.press("Enter");
  await expect(page.locator("#issue-state")).toHaveText("closed");
});
