import { expect, test } from "@playwright/test";

declare global {
  interface Window {
    cspViolations: string[];
  }
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.cspViolations.push(`${event.violatedDirective} ${event.blockedURI}`);
    });
  });
});

for (const path of ["/", "/estoque/produtos/42"]) {
  test(`renders ${path} under the production CSP without violations`, async ({ page }) => {
    const response = await page.goto(path);

    expect(response?.status()).toBe(200);
    expect(response?.headers()["content-security-policy"]).toContain("default-src 'none'");
    await expect(page.getByRole("heading", { name: "Alicerce" })).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
  });
}
