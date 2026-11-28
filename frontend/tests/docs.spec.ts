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
  const anchor = page.locator("article h2 .docs-anchor").first();
  await expect(anchor).toHaveAttribute("aria-label", "Link to this section");
  await expect(page.locator('aside[aria-labelledby="toc-heading"]')).toBeVisible();
});

test("docs navigation opens and closes from the keyboard on small screens", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/docs/claims/");
  const toggle = page.getByRole("button", { name: /Docs menu/i });
  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("#docs-nav-list")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
});

test("docs tables and code blocks have scroll containers", async ({ page }) => {
  await page.goto("/docs/claims/");
  await expect(page.locator(".docs-table-wrap").first()).toBeVisible();
  expect(await page.locator(".docs-table-wrap table").count()).toBeGreaterThan(0);
  await page.goto("/docs/how-it-works/");
  await expect(page.locator(".docs-code").first()).toBeVisible();
  await expect(page.getByRole("button", { name: "Copy code" }).first()).toBeVisible();
});

test("docs do not render claim tokens", async ({ page }) => {
  await page.goto("/docs/claims/");
  await expect(page.getByText(/claim:RUD-\d+/)).toHaveCount(0);
});

test("docs navigation adapts across breakpoints", async ({ page }) => {
  await page.setViewportSize({ width: 768, height: 800 });
  await page.goto("/docs/how-it-works/");
  await expect(page.getByRole("button", { name: /Docs menu/i })).toBeVisible();
  await expect(page.locator("#docs-nav-list")).toBeHidden();
  await page.setViewportSize({ width: 1280, height: 800 });
  await expect(page.getByRole("button", { name: /Docs menu/i })).toBeHidden();
  await expect(page.locator("#docs-nav-list")).toBeVisible();
  await expect(page.locator('aside[aria-labelledby="toc-heading"]')).toBeVisible();
});

for (const width of [375, 768, 1280]) {
  for (const slug of ["", "claims/", "deployments/", "how-it-works/"]) {
    test(`docs /docs/${slug} has no horizontal page scroll at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 812 });
      await page.goto(`/docs/${slug}`);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(overflow).toBeLessThanOrEqual(1);
      const scrollerStyles = await page.$$eval(".docs-table-wrap, .docs-prose pre", (elements) =>
        elements.map((element) => getComputedStyle(element).overflowX),
      );
      expect(scrollerStyles.every((value) => value === "auto")).toBe(true);
    });
  }
}
