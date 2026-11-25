import { expect, test } from "@playwright/test";

test("home exposes the deposit, judge path and documentation routes", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "Deposit", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open the full judge path" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Read the docs" })).toBeVisible();
});

test("curators page states the ranking rule", async ({ page }) => {
  await page.goto("/curators/");
  await expect(page.getByText("Deposits are", { exact: false }).first()).toBeVisible();
  await expect(page.getByText("All scores tied at zero")).toBeVisible();
});

test("proof page offers a signature-free simulation", async ({ page }) => {
  await page.goto("/proof/");
  await expect(page.getByRole("button", { name: "Simulate rebalance" })).toBeVisible();
  await expect(page.getByText("No wallet is connected", { exact: false })).toBeVisible();
});

test("judge path includes mint, snapshot fallback and no key input", async ({ page }) => {
  await page.goto("/try/");
  await expect(page.getByRole("button", { name: "Mint", exact: true })).toBeVisible();
  await expect(page.getByText("Snapshot fallback")).toBeVisible();
  expect(await page.locator('input[type="password"]').count()).toBe(0);
});

test("wrong network copy is present before a wallet connects", async ({ page }) => {
  await page.goto("/positions/");
  await expect(page.getByText("Connect a wallet from the header", { exact: false })).toBeVisible();
});
