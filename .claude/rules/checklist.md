# Checklist pós-implementação

> Rodar o bloco correspondente ao domínio tocado ANTES de commitar / abrir PR. Se qualquer item falhar, corrigir antes de prosseguir.

## ✅ Geral (todo PR)

- [ ] `npm run typecheck` sem erros
- [ ] `npm run lint` sem erros (ou warnings justificados em comentário)
- [ ] `npm run format:check` limpo
- [ ] `npm run build` local passa
- [ ] Nada de `console.log`, `TODO`, `FIXME` solto — ou issue criada
- [ ] Sem `any`, `@ts-ignore`, `@ts-expect-error` sem justificativa
- [ ] Arquivos ≤ 300 linhas; funções ≤ 50; componentes ≤ 200
- [ ] UI, commits, JSDoc e mensagens em **PT-BR**
- [ ] Nada fora do escopo pedido
- [ ] PR com **Contexto / Mudanças / Como testar / Checklist** preenchido

## 🔐 Segurança

- [ ] Nenhum segredo/env key em diff
- [ ] `SUPABASE_SERVICE_ROLE_KEY` usado SOMENTE em `lib/supabase/admin.ts` (ou arquivo `server-only`)
- [ ] `NEXT_PUBLIC_*` não contém dado sensível
- [ ] Zod valida TODA entrada externa (Server Action, Route Handler, webhook)
- [ ] Middleware protege `/admin/*`
- [ ] Rotas públicas de mutação têm rate limit + captcha
- [ ] Webhooks validam assinatura do emissor (Stripe/WhatsApp)
- [ ] Logs não expõem PII (telefone, email, CPF em texto claro)
- [ ] `audit_logs` registra ação sensível (cancelar, mudar preço/comissão, excluir)
- [ ] Security headers configurados no `next.config.js`
- [ ] `npm audit --omit=dev` sem CRITICAL/HIGH abertos

## 🏢 Multi-tenant

- [ ] Toda tabela nova tem `tenant_id uuid NOT NULL REFERENCES tenants(id)`
- [ ] `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` aplicado
- [ ] Policies SELECT / INSERT / UPDATE / DELETE por tenant_id criadas
- [ ] Policies adicionais por `role` quando necessário (professional só vê o seu)
- [ ] Índice composto começando por `tenant_id`
- [ ] Queries no código filtram explicitamente por `tenant_id` (não dependem só de RLS)
- [ ] Teste: usuário do tenant A NÃO enxerga linha do tenant B via API
- [ ] Teste: anon (LP pública) só enxerga `active = true` do tenant do `slug`
- [ ] Feature funciona para QUALQUER tenant (nada hardcoded)
- [ ] Checagem de plano via `assertFeature` onde aplicável
- [ ] `types/database.ts` regenerado (`npm run db:types`)

## 🗄️ Supabase / Postgres

- [ ] Migration em `supabase/migrations/` versionada (timestamp correto)
- [ ] Migration é idempotente quando possível (`IF NOT EXISTS`)
- [ ] Rollback manual documentado no topo do arquivo se não for trivial
- [ ] NÃO editou migration já aplicada em produção (criou nova ao invés)
- [ ] FK com `ON DELETE` explícito (`CASCADE | RESTRICT | SET NULL`)
- [ ] Colunas com default sensato e `NOT NULL` quando cabe
- [ ] Enum novo criado com `CREATE TYPE` antes de usar
- [ ] `updated_at timestamptz` + trigger quando houver edição (padrão Supabase)

## 📱 Frontend (Next.js)

- [ ] Server Components por padrão; `"use client"` só onde necessário
- [ ] Nenhum segredo em bundle client (checar com `next build` output)
- [ ] `next/image` em todas as imagens; `next/font` para fontes
- [ ] LP pública é SSG/ISR — não virou CSR acidentalmente
- [ ] `Suspense` + streaming em listas/dashboards
- [ ] Estado derivado derivado no render (não em `useEffect`)
- [ ] Formulários com `react-hook-form` + Zod, mensagens PT-BR
- [ ] Sem biblioteca pesada no bundle público (checar com `@next/bundle-analyzer` quando aplicável)

## ⚡ Performance

- [ ] LP pública < 1s em Lighthouse mobile (simulação 4G)
- [ ] Queries frequentes usam índices compostos
- [ ] Sem N+1 — confirmado via `explain analyze` em queries complexas
- [ ] Paginação em listas com potencial de crescer (clientes, agendamentos)
- [ ] Cache (`unstable_cache`, `revalidateTag`) em leituras quentes
- [ ] Imagens otimizadas, com `sizes` correto

## 🧪 Qualidade (quando houver testes — V2)

- [ ] Regras de negócio críticas cobertas (disponibilidade, transição de status, cálculo de comissão)
- [ ] Testes passam local e em CI
- [ ] Snapshot só para coisas realmente estáveis

## 📦 Deploy

- [ ] Variáveis de ambiente configuradas na Vercel
- [ ] `SUPABASE_SERVICE_ROLE_KEY` marcada como **secret**
- [ ] Preview deploy testado com tenant de staging
- [ ] Domínio `dunee.com.br` aponta corretamente (produção)
- [ ] Rollback plan: última tag estável identificada
- [ ] Migração aplicada em staging ANTES de produção

## 📜 Git / GitHub

- [ ] `gh auth status` → conta `ViniciusMolinari`
- [ ] Branch no padrão `tipo/kebab-case`
- [ ] Commits Conventional em PT-BR
- [ ] Sem `--no-verify`
- [ ] PR tem descrição completa + checklist marcado
- [ ] Base = `main`

## 🎨 Identidade Visual

- [ ] Sem hex/rgb hardcoded — só tokens Tailwind ou CSS vars
- [ ] Contraste AA mínimo (texto `--text` sobre `--bg-card`)
- [ ] Light theme (Atelier Lumière) consistente — sem `dark:` prefix espalhado
- [ ] Copy em PT-BR, sem gírias, direto
