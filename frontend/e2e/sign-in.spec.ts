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

  // A demo account, owner role or not, never gets member management (ADR
  // 0008): the nav link must not even appear, not just be blocked server side.
  await expect(page.getByRole("link", { name: "Membros" })).not.toBeVisible();

  // Unlike member management, master data is not demo-gated (ADR 0008): a
  // demo owner can still see and manage the seeded catalog.
  await page.getByRole("link", { name: "Produtos" }).click();
  await expect(page.getByRole("heading", { name: "Produtos" })).toBeVisible();
  await expect(page.getByText("TIJ-001")).toBeVisible();
  await expect(page.getByRole("button", { name: "Novo produto" })).toBeVisible();

  await page.getByRole("button", { name: "Sair" }).click();

  await expect(page.getByRole("heading", { name: "Entrar" })).toBeVisible();
});
