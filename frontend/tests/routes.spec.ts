import { expect, test } from "@playwright/test";

const routes = [
  { path: "/", heading: "Curators steer" },
  { path: "/curators/", heading: "Curators, ordered by alpha alone." },
  { path: "/curators/0/", heading: "Curator 0x" },
  { path: "/positions/", heading: "Your position, your exit." },
  { path: "/console/", heading: "Every move has a stated limit." },
  { path: "/proof/", heading: "A rejected move" },
  { path: "/evidence/", heading: "What we measured — and what we did not." },
  { path: "/protocol/", heading: "One pool, one range, enforced twice." },
  { path: "/try/", heading: "Fund, deposit, prove the guard, exit." },
  { path: "/docs/", heading: "Documentation" },
];

for (const route of routes) {
  test(`${route.path} renders`, async ({ page }) => {
    await page.goto(route.path);
    await expect(page.locator("h1").first()).toContainText(route.heading);
    await expect(page.locator("footer")).toBeVisible();
  });
}

test("no password inputs are rendered", async ({ page }) => {
  for (const route of routes) {
    await page.goto(route.path);
    expect(await page.locator('input[type="password"]').count()).toBe(0);
  }
});
