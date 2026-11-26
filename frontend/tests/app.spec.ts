import { expect, test } from "@playwright/test";

const uiRoutes = [
  "/",
  "/vaults/",
  "/vaults/0/",
  "/deposits/",
  "/for-curators/",
  "/proof/",
  "/evidence/",
  "/contracts/",
  "/try/",
  "/docs/",
  "/curators/",
  "/positions/",
  "/console/",
  "/protocol/",
];

test("home exposes the simplified entry points and footer docs link", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Trust the rules, not the manager.");
  await expect(page.getByRole("link", { name: "Try it in two minutes" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Try to break the rules" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Pick a curator" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Read the docs" })).toBeVisible();
});

test("home shows sourced numbers without a chart", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText("Withdrawals that depend on a price feed")).toBeVisible();
  await expect(page.getByText("Limits a curator cannot exceed")).toBeVisible();
  await expect(page.locator("svg")).toHaveCount(0);
});

test("curators page states the ranking rule in plain language", async ({ page }) => {
  await page.goto("/vaults/");
  await expect(page.getByText("Deposits are displayed but never ranked")).toBeVisible();
  await expect(page.getByText("All scores tied at zero")).toBeVisible();
  await expect(page.getByRole("columnheader", { name: "Return vs holding" })).toBeVisible();
});

test("proof page offers a signature-free simulation", async ({ page }) => {
  await page.goto("/proof/");
  await expect(page.getByRole("button", { name: "Simulate rebalance" })).toBeVisible();
  await expect(page.getByText("No wallet is connected", { exact: false })).toBeVisible();
});

test("try path includes mint, recorded state and no key input", async ({ page }) => {
  await page.goto("/try/");
  await expect(page.getByRole("button", { name: "Mint", exact: true })).toBeVisible();
  await expect(page.getByText("Recorded chain state")).toBeVisible();
  expect(await page.locator('input[type="password"]').count()).toBe(0);
});

test("deposits page asks for a wallet connection", async ({ page }) => {
  await page.goto("/deposits/");
  await expect(page.getByText("Connect a wallet from the header", { exact: false })).toBeVisible();
});

test("pages have one headline, no eyebrow labels and one footer docs link", async ({ page }) => {
  for (const path of uiRoutes) {
    await page.goto(path);
    expect(await page.locator("h1").count()).toBe(1);
    expect(await page.locator(".eyebrow").count()).toBe(0);
    await expect(page.getByRole("link", { name: "Read the docs" })).toHaveCount(1);
  }
});

test("non-docs pages avoid the old jargon", async ({ page }) => {
  for (const path of uiRoutes.filter((route) => !route.startsWith("/docs/"))) {
    await page.goto(path);
    const text = await page.locator("body").innerText();
    expect(text).not.toMatch(/\b(envelope|alpha|guard)\b/i);
  }
});

test("technical tables explain their headers", async ({ page }) => {
  for (const path of ["/vaults/0/", "/evidence/", "/contracts/"]) {
    await page.goto(path);
    await expect(page.locator("table caption").first()).toBeVisible();
  }
});
