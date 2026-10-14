import { expect, test } from "@playwright/test";
import { openPage } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("a sequence runs an action while the palette is closed", async ({ page }) => {
  await page.keyboard.press("g");
  await page.keyboard.press("p");
  await expect(page.locator("#people-title")).toBeVisible();
  await expect(page.locator(".jumon-dialog")).toBeHidden();
});

test("single keys do nothing in a text field", async ({ page }) => {
  await page.evaluate(() => {
    const field = document.createElement("input");
    field.id = "field";
    document.querySelector("main")!.prepend(field);
  });
  await page.locator("#field").focus();
  await page.keyboard.type("gpc");
  await expect(page.locator("#field")).toHaveValue("gpc");
  await expect(page.locator("#issues")).toBeVisible();
});

test("? lists the keyboard shortcuts", async ({ page }) => {
  await page.keyboard.press("Shift+?");
  await expect(page.locator(".jumon-crumb")).toHaveText(["Keyboard shortcuts"]);
  await expect(page.locator(".jumon-list [role=option]").filter({ hasText: "People" }).locator("kbd")).toHaveText(["G", "P"]);
});

test("the button shows the shortcut of the platform", async ({ page }) => {
  await expect(page.locator(".jumon-button [data-jumon-formatted]")).toBeAttached();
  const keys = await page.locator(".jumon-button kbd").allTextContents();
  expect(keys.join("")).toMatch(/^(⌘K|CtrlK)$/);
});
