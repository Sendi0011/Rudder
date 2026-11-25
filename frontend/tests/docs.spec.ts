import { expect, test } from "@playwright/test";
import manifest from "../content/manifest.json";

const groups = ["Design", "Assurance", "Deployment"];

test("docs index has grouped navigation", async ({ page }) => {
  await page.goto("/docs/");
  for (const group of groups) {
    await expect(page.getByText(group, { exact: true }).first()).toBeVisible();
  }
  await expect(page.locator('nav[aria-label="Documentation"] a').first()).toBeVisible();
});

for (const doc of manifest.filter((entry) => entry.slug !== "index")) {
  test(`docs route /docs/${doc.slug}/ renders`, async ({ page }) => {
    await page.goto(`/docs/${doc.slug}/`);
    await expect(page.locator("h1").first()).toHaveText(doc.title);
    await expect(page.getByText("Rendered from commit", { exact: false }).first()).toBeVisible();
    const badLinks = await page.$$eval("a[href]", (links) =>
      links
        .map((link) => link.getAttribute("href") || "")
        .filter((href) => href.endsWith(".md") && !href.startsWith("http")),
    );
    expect(badLinks).toEqual([]);
  });
}

test("docs headings have anchor ids and a table of contents", async ({ page }) => {
  await page.goto("/docs/how-it-works/");
  expect(await page.locator("article h2[id]").count()).toBeGreaterThan(0);
  await expect(page.locator('aside[aria-labelledby="toc-heading"]')).toBeVisible();
});
