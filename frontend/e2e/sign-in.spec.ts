import { expect, test } from "@playwright/test";

const seedPassword = process.env.SEED_USER_PASSWORD;

test.skip(
  !seedPassword,
  "SEED_USER_PASSWORD is not set; export it to match how the server under test was seeded.",
);

test("signs in as a seeded demo user, lands on the app shell, then signs out", async ({ page }) => {
  if (!seedPassword) throw new Error("unreachable: skipped by test.skip above");

  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Entrar" })).toBeVisible();

  await page.getByLabel("E-mail").fill("joana.lima@canion.example");
  await page.getByLabel("Senha").fill(seedPassword);
  await page.getByRole("button", { name: "Entrar" }).click();

  await expect(page.getByRole("heading", { name: /Joana Lima/ })).toBeVisible();
  await expect(page.getByText("Cânion Materiais de Construção")).toBeVisible();

  await page.getByRole("button", { name: "Sair" }).click();

  await expect(page.getByRole("heading", { name: "Entrar" })).toBeVisible();
});
