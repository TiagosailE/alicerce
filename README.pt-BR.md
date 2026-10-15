# Alicerce

[![CI](https://github.com/TiagosailE/alicerce/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/TiagosailE/alicerce/actions/workflows/ci.yml)
[![Scheduled audit](https://github.com/TiagosailE/alicerce/actions/workflows/audit.yml/badge.svg)](https://github.com/TiagosailE/alicerce/actions/workflows/audit.yml)
[![CodeQL](https://github.com/TiagosailE/alicerce/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/TiagosailE/alicerce/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Read in English](README.md)

ERP multiempresa para pequenas distribuidoras brasileiras. O núcleo é o ciclo fechado de compras, estoque, vendas e financeiro, em que cada etapa deixa as outras consistentes: receber mercadoria aumenta o estoque e gera a conta a pagar na mesma transação, e faturar uma venda vai baixar o estoque e gerar as contas a receber do mesmo jeito. As regras de consistência ficam no domínio e, onde o Postgres consegue expressá-las, também no banco.

A empresa de demonstração é uma distribuidora fictícia de materiais de construção em Paulo Afonso, Bahia, que compra tijolo por milheiro e cimento por saco e vende por unidade. Uma segunda empresa, menor, existe para provar que uma organização nunca enxerga os dados de outra. Todo nome, CPF e CNPJ dos seeds é gerado.

![Saldos de estoque por produto e depósito](docs/screenshots/stock-balances.png)

## Situação

**Em desenvolvimento.** O projeto é construído em fatias verticais, cada uma indo da migration à tela, com autorização, isolamento entre empresas e o documento OpenAPI atualizados juntos. Ainda não está publicado; o plano de hospedagem está em [docs/deploy.md](docs/deploy.md).

| # | Fatia | Situação |
|---|---|---|
| 0 | Fundação: CI, varreduras de segurança, imagem Docker, documentos de arquitetura e segurança | pronta |
| 1 | Identidade e acesso: organizações, papéis, sessões, convites, trilha de auditoria | pronta (aceite de convite e redefinição de senha ainda sem tela) |
| 2 | Cadastros: produtos, unidades com conversão de compra, categorias, depósitos, clientes e fornecedores | pronta |
| 3 | Estoque: saldos, livro de movimentações só de inserção, ajustes de contagem pelo custo médio | pronta |
| 4 | Compras: pedidos de compra, recebimentos parciais, contas a pagar | pronta |
| 5 | Vendas: reserva, faturamento que baixa o estoque de forma atômica, cancelamento | próxima |
| 6 | Financeiro: baixas, estornos, vencidos, posição de caixa | planejada |
| 7 | Endurecimento: TOTP, gestão de sessões | planejada |

Escopo completo, invariantes e roteiro em [docs/scope.md](docs/scope.md) (em inglês, como toda a documentação técnica).

## Telas

| | |
|---|---|
| ![Pedido de compra](docs/screenshots/purchase-order.png) | ![Recebimento](docs/screenshots/receive.png) |
| Pedido de compra recebido em parte: 120 de 200 sacos até agora | Recebendo o restante, com uma etapa de revisão antes de gravar qualquer coisa |
| ![Recebimento registrado](docs/screenshots/receipt.png) | ![Contas a pagar](docs/screenshots/payables.png) |
| O recebimento: estoque entra pelo custo do pedido, desconto discriminado, conta a pagar aberta | Contas a pagar geradas pelos recebimentos, divididas em parcelas |
| ![Livro de movimentações](docs/screenshots/stock-movements.png) | ![Tema escuro](docs/screenshots/stock-balances-dark.png) |
| Movimentações de estoque, cada uma com valor e o saldo depois dela | Tema escuro |

A interface é em português do Brasil; código, API e documentação são em inglês.

## Destaques de arquitetura

- **Isolamento entre empresas em duas camadas.** Toda tabela de empresa tem `organization_id`, o escopo da aplicação falha fechado sem uma organização corrente e o row level security do Postgres filtra toda consulta por uma configuração definida a cada requisição. A suíte inteira de testes conecta com o mesmo papel não superusuário que a aplicação usa em produção, então todo teste roda sob RLS, e testes em SQL puro provam que as linhas de outra organização ficam invisíveis. Um teste de inventário de rotas quebra o build quando uma rota de `/api/v1` não tem teste de isolamento. ([ADR 0003](docs/adr/0003-tenant-isolation.md))
- **Livro de estoque só de inserção.** O estoque vive em uma linha de saldo por produto e depósito mais um livro imutável de movimentações, cada uma com quantidade, valor e o saldo depois dela. UPDATE, DELETE e TRUNCATE são recusados por privilégios e triggers, e um CHECK impede o saldo de ficar negativo sem uma autorização registrada. ([ADR 0016](docs/adr/0016-stock-balances-ledger-and-count-adjustments.md))
- **Locks pessimistas em uma ordem global.** Todo comando que mexe em estoque trava as linhas na mesma ordem (chave de idempotência, documentos e linhas, saldos por produto e depósito, títulos, contadores), com um lock timeout que responde `409 conflict_retry` em vez de travar a requisição. Os testes de concorrência soltam threads reais ao mesmo tempo. ([ADR 0004](docs/adr/0004-stock-locking.md))
- **Escritas críticas idempotentes.** Recebimento de mercadoria e ajuste de estoque (e, em seguida, faturamento e baixas) exigem um `Idempotency-Key`; repetir a requisição devolve o resultado original e a mesma chave com outra requisição é recusada. ([ADR 0005](docs/adr/0005-idempotency-keys.md))
- **Concorrência otimista nos cadastros.** Editar um produto, um parceiro ou um pedido de compra em rascunho envia de volta a `revision` lida; se o servidor já tiver uma mais nova, responde `409 stale` e não grava nada, então duas pessoas editando ao mesmo tempo nunca sobrescrevem uma à outra em silêncio. ([ADR 0015](docs/adr/0015-concurrent-edits-and-master-data-that-documents-reference.md))
- **Dinheiro em centavos inteiros.** Nenhum float no caminho do dinheiro, quantidades com três casas decimais e todo arredondamento acontece em um ponto nomeado, inclusive a divisão de um total em parcelas. ([ADR 0006](docs/adr/0006-money-and-quantities.md))
- **Máquinas de estado explícitas e trilha de auditoria.** Pedidos, recebimentos e títulos só mudam de estado por tabelas de transição no modelo; toda mudança relevante grava um evento de auditoria que o banco protege contra UPDATE e DELETE. ([ADR 0009](docs/adr/0009-state-machines.md), [ADR 0010](docs/adr/0010-audit-trail.md))
- **API com o esquema primeiro.** O documento OpenAPI é escrito antes do código, os testes de requisição validam cada resposta contra ele e o cliente TypeScript do SPA é gerado a partir dele; o CI falha se os tipos gerados divergirem. ([ADR 0011](docs/adr/0011-openapi-schema-first.md))
- **Segurança como checklist com evidência.** Um [threat model](docs/threat-model.md) STRIDE sobre login, faturamento e estoque, e um [checklist de segurança](docs/security.md) mirando o OWASP ASVS nível 2, em que cada controle aponta para o código ou o teste. CPF e CNPJ são criptografados em repouso e mascarados nas listas ([ADR 0012](docs/adr/0012-personal-data-encryption.md), [ADR 0014](docs/adr/0014-partner-personal-data-visibility.md)).

Dezessete ADRs (registros de decisão de arquitetura) explicam as escolhas difíceis de desfazer: [docs/adr](docs/adr/README.md). Como as peças se encaixam está em [docs/architecture.md](docs/architecture.md).

## Stack

| Camada | Escolha |
|---|---|
| Backend | Ruby 4.0, Rails 8.1 em modo API, Pundit, Solid Queue e Solid Cache no Postgres |
| Banco | PostgreSQL 18 com row level security, esquema mantido em `db/structure.sql` |
| Frontend | React 19, TypeScript, Vite, Tailwind CSS 4, TanStack Query, cliente tipado a partir do documento OpenAPI |
| Testes | RSpec (piso de cobertura de 90% de linhas e 80% de ramos), Vitest com Testing Library, Playwright contra a imagem de produção |
| CI | GitHub Actions: lint, tipos, auditorias, Brakeman, testes, a imagem de produção subindo com orçamento de memória, um teste de navegador que falha em qualquer violação de CSP, Trivy, gitleaks, dependency review, CodeQL |
| Hospedagem (planejada) | Uma imagem Docker no Render, Postgres no Supabase ([ADR 0002](docs/adr/0002-free-hosting.md)) |

## Rodando localmente

Requisitos: Ruby 4.0.7 e Node 24 (versões em `.ruby-version` e `.node-version`, lidas pelo mise) e Docker para o Postgres.

```sh
git clone https://github.com/TiagosailE/alicerce.git
cd alicerce
bin/setup
```

O `bin/setup` instala as dependências, sobe o Postgres com Docker Compose em 127.0.0.1:5433, cria e popula o banco e inicia o Rails (porta 3000) e o Vite (porta 5173). Abra http://localhost:5173 e entre com um usuário dos seeds; em desenvolvimento todos usam a senha `alicerce-demo-2026`.

| Usuário | Papel | Empresa |
|---|---|---|
| `joana.lima@canion.example` | owner | Cânion Materiais de Construção |
| `bruno.tavares@canion.example` | purchasing | Cânion Materiais de Construção |
| `rafael.souza@canion.example` | sales | Cânion Materiais de Construção |
| `marcia.alves@canion.example` | finance | Cânion Materiais de Construção |
| `pedro.rocha@serradourada.example` | owner | Ferragens Serra Dourada |

O `bin/ci` roda todas as verificações que funcionam localmente. Os demais comandos, a organização das pastas e as convenções estão no [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

[MIT](LICENSE)
