import { expect, test } from "@playwright/test";

const routes = [
  { path: "/", heading: "Trust the rules, not the manager." },
  { path: "/vaults/", heading: "Pick a curator." },
  { path: "/vaults/0/", heading: "Curator 0x" },
  { path: "/deposits/", heading: "Your deposits." },
  { path: "/for-curators/", heading: "For curators." },
  { path: "/proof/", heading: "Try to break the rules." },
  { path: "/evidence/", heading: "What we measured." },
  { path: "/contracts/", heading: "Contracts." },
  { path: "/try/", heading: "Try it in two minutes." },
  { path: "/docs/", heading: "Documentation" },
];

const legacyRoutes = [
  "/curators/",
  "/curators/0/",
  "/positions/",
  "/console/",
  "/protocol/",
];

for (const route of routes) {
  test(`${route.path} renders`, async ({ page }) => {
    await page.goto(route.path);
    await expect(page.locator("h1").first()).toContainText(route.heading);
    await expect(page.locator("footer")).toBeVisible();
  });
}

test("legacy routes still render", async ({ page }) => {
  for (const path of legacyRoutes) {
    await page.goto(path);
    await expect(page.locator("h1").first()).toBeVisible();
    await expect(page.locator("footer")).toBeVisible();
  }
});

test("no password inputs are rendered", async ({ page }) => {
  for (const route of [...routes, ...legacyRoutes.map((path) => ({ path }))]) {
    await page.goto(route.path);
    expect(await page.locator('input[type="password"]').count()).toBe(0);
  }
});
