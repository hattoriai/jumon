import { expect, test } from "@playwright/test";
import { active, input, openPage, openPalette, search } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("an action asks for its arguments, then runs on the server", async ({ page }) => {
  await openPalette(page);
  await search(page, "assign", "Assign to…");
  await page.keyboard.press("Enter");
  await expect(input(page)).toHaveAttribute("placeholder", "Which issue?");
  await search(page, "ship", "Ship the command palette");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-crumb")).toHaveText(["Assign to…", "Issue: Ship the command palette"]);
  await expect(input(page)).toHaveAttribute("placeholder", "Assign to whom?");
  // The people come from a search that runs in a task of the LiveView.
  await search(page, "radia", "Radia Perlman");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-dialog")).toBeHidden();
  await expect(page.locator("#flash")).toHaveText("Assigned to Radia Perlman");
  await expect(page.locator("#issue-2")).toContainText("Radia Perlman");
});

test("a choice of options", async ({ page }) => {
  await openPalette(page);
  await search(page, "priority", "Set priority…");
  await page.keyboard.press("Enter");
  await search(page, "guides", "Write the guides of the palette");
  await page.keyboard.press("Enter");
  await search(page, "lo", "Low");
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toHaveText("Priority set");
  await expect(page.locator("#issue-6")).toContainText("low");
});

test("an action to confirm: Escape cancels, Enter confirms", async ({ page }) => {
  await openPalette(page);
  await search(page, "archive", "Archive the closed issues");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-message")).toContainText("Archive every closed issue?");
  await page.keyboard.press("Escape");
  await expect(page.locator(".jumon-message")).toBeHidden();
  await expect(page.locator(".jumon-dialog")).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-message")).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toHaveText("Archived");
  await expect(page.locator("[data-state=closed]")).toHaveCount(0);
});

test("the shortcut of an action with arguments opens its page", async ({ page }) => {
  await page.keyboard.press("a");
  await expect(page.locator(".jumon-dialog")).toBeVisible();
  await expect(page.locator(".jumon-crumb")).toHaveText(["Assign to…"]);
  await expect(active(page)).toBeVisible();
});
