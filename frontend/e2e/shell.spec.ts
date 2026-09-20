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
    // Neither path has a session cookie, so both redirect client-side to the
    // sign-in screen; that redirect happening at all is itself evidence the
    // shell booted and CSP-safe scripts ran.
    await expect(page.getByRole("heading", { name: "Entrar" })).toBeVisible();
    expect(await page.evaluate(() => window.cspViolations)).toEqual([]);
  });
}

test("detects a violation, so the checks above cannot pass vacuously", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => {
    const style = document.createElement("style");
    style.textContent = "body { color: red }";
    document.head.append(style);
  });

  await expect.poll(() => page.evaluate(() => window.cspViolations.length)).toBeGreaterThan(0);
});
