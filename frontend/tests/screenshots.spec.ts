import { expect, test } from "@playwright/test";
import manifest from "../content/manifest.json";

const routes = [
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
  ...manifest.filter((entry) => entry.slug !== "index").map((entry) => `/docs/${entry.slug}/`),
];

const viewports = [
  { name: "desktop", width: 1280, height: 900 },
  { name: "mobile", width: 390, height: 844 },
];

test.skip(!process.env.SCREENSHOT_DIR, "SCREENSHOT_DIR is not set");

for (const route of routes) {
  for (const viewport of viewports) {
    test(`screenshot ${route} at ${viewport.name}`, async ({ page }) => {
      test.setTimeout(120_000);
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      await page.goto(route);
      await expect(page.locator("h1").first()).toBeVisible();
      const slug = route === "/" ? "home" : route.replace(/^\/|\/$/g, "").replace(/\//g, "__");
      await page.screenshot({
        path: `${process.env.SCREENSHOT_DIR}/${slug}-${viewport.name}.png`,
        fullPage: true,
      });
    });
  }
}
