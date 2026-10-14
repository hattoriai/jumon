import { expect, test } from "@playwright/test";
import { active, input, mod, names, openPage, openPalette, option, search } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("opens with its shortcut and closes with Escape, giving the focus back", async ({ page }) => {
  const button = page.locator(".jumon-button");
  await button.focus();
  const dialog = await openPalette(page);
  await expect(page.locator(".jumon-heading").first()).toHaveText("Go to");
  await expect(active(page)).toContainText("Issues");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(button).toBeFocused();
});

test("the button opens it, and the shortcut closes it again", async ({ page }) => {
  await page.locator(".jumon-button").click();
  await expect(page.locator(".jumon-dialog")).toBeVisible();
  await page.keyboard.press(`${await mod(page)}+k`);
  await expect(page.locator(".jumon-dialog")).toBeHidden();
});

test("filters as one types, marks what matched, and navigates", async ({ page }) => {
  await openPalette(page);
  await search(page, "ppl", "People");
  await expect(active(page).locator("mark.jumon-match")).toHaveText(["P", "pl"]);
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-dialog")).toBeHidden();
  await expect(page.locator("#people-title")).toBeVisible();
  await expect(page).toHaveURL(/\/people$/);
});

test("arrows, Ctrl+N and Ctrl+P move through the results, past the headings", async ({ page }) => {
  await openPalette(page);
  await expect(active(page)).toContainText("Issues");
  await page.keyboard.press("ArrowDown");
  await expect(active(page)).toContainText("People");
  await page.keyboard.press("Control+n");
  await expect(active(page)).toContainText("A page without LiveView");
  await page.keyboard.press("Control+p");
  await page.keyboard.press("ArrowUp");
  await expect(active(page)).toContainText("Issues");
  // Up from the first wraps to the last.
  await page.keyboard.press("ArrowUp");
  await expect(active(page)).toContainText("Keyboard shortcuts");
});

test("keywords, typos and accents find actions", async ({ page }) => {
  await openPalette(page);
  await search(page, "logout", "Sign out");
  await search(page, "isues");
  await expect(option(page, "Issues")).toBeVisible();
  await search(page, "PÉOPLE", "People");
});

test("a search with no result says so", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("zzzzqx");
  await expect(page.locator(".jumon-status-empty")).toHaveText("No results");
});

test("an action that pushes an event to the LiveView", async ({ page }) => {
  await openPalette(page);
  await search(page, "new issue", "New issue");
  await page.keyboard.press("Enter");
  await expect(page.locator("#flash")).toContainText("Created");
});

test("an action that copies a text", async ({ page, context, browserName }) => {
  test.skip(browserName !== "chromium", "clipboard permissions");
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openPalette(page);
  await search(page, "copy the time", "Copy the time on the server");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-dialog")).toBeHidden();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toMatch(/^\d{4}-\d\d-\d\dT/);
});

test("a disabled action says why", async ({ page }) => {
  await openPalette(page);
  await search(page, "billing", "Billing");
  await expect(active(page)).toHaveAttribute("aria-disabled", "true");
  await page.keyboard.press("Enter");
  await expect(page.locator(".jumon-message")).toContainText("Only the owner sees billing");
});

test("a click runs an action, and the backdrop closes the palette", async ({ page }) => {
  await openPalette(page);
  await page.mouse.click(10, 10);
  await expect(page.locator(".jumon-dialog")).toBeHidden();
  await openPalette(page);
  await option(page, "People").first().click();
  await expect(page.locator("#people-title")).toBeVisible();
});

test("what one runs comes back under Recent", async ({ page }) => {
  await openPalette(page);
  await search(page, "people", "People");
  await page.keyboard.press("Enter");
  await expect(page.locator("#people-title")).toBeVisible();
  await openPalette(page);
  await expect(page.locator(".jumon-heading").first()).toHaveText("Recent");
  expect(await names(page)).toContain("People");
  await expect(page.locator(".jumon-recent").first()).toBeVisible();
});

test("an app's own focus outline stays off the box", async ({ page }) => {
  // As an app's style sheet does: as specific as .jumon-input, and later.
  await page.addStyleTag({ content: ":focus-visible { outline: 2px solid red; }" });
  await openPalette(page);
  await expect(input(page)).toHaveCSS("outline-style", "none");
});
