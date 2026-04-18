# CLAUDE.md — Dunee 001

> Índice compacto de regras. Detalhes em `.claude/rules/*.md`. Em caso de dúvida, consulte o arquivo detalhado correspondente.

**Projeto:** Dunee 001 — SaaS B2B multi-tenant para salões de beleza, barbearias e profissionais autônomos de estética.
**Domínio:** `dunee.com.br` (produção) — NUNCA hardcodar subdomínios provisórios da Vercel.
**Repositório:** `github.com/ViniciusMolinari/dunee001` (conta `ViniciusMolinari`).
**Stack:** Next.js 16 + React 19 + TypeScript + Tailwind 4 + Supabase (Postgres/Auth/Storage/Realtime) + Vercel.
**Idioma:** PT-BR em TODA comunicação, comentários, mensagens de UI e commits.

---

## 🧭 3 REGRAS FUNDAMENTAIS (NUNCA VIOLAR)

1. **SEGURANÇA É PRIORIDADE ABSOLUTA** — SaaS armazena dados pessoais (CPF, telefone, email), financeiros (comissões, receitas) e de múltiplos tenants. NUNCA expor dados de um tenant a outro. NUNCA confiar apenas no client-side — RLS no Postgres é a linha de defesa final.
2. **MULTI-TENANT: TUDO É REPLICÁVEL** — Toda feature nasce funcionando para TODOS os tenants (salões/barbearias/autônomos). NUNCA criar algo específico para um tenant. Estrutura Postgres sempre com `tenant_id` + RLS. Se o usuário pedir "módulo de estoque", TODOS os tenants ganham automaticamente.
3. **ANTES DE CODAR, EXPLORAR E PERGUNTAR** — SEMPRE ler os arquivos antes de escrever. NUNCA deduzir estrutura. NUNCA criar componente/hook/util sem verificar se já existe. SEMPRE apresentar plano e aguardar aprovação. Se houver >1 abordagem, apresentar opções — quem decide é o usuário.

---

## 1. REGRAS OBRIGATÓRIAS DE TRABALHO

- SEMPRE explorar a estrutura do projeto antes de qualquer edição (`src/`, `supabase/`, `package.json`, migrations existentes).
- SEMPRE apresentar plano com etapas + arquivos afetados ANTES de implementar. Aguardar "pode" / "prossiga".
- SEMPRE apresentar opções quando existir mais de uma abordagem razoável (ex: Server Action vs API Route). Usuário decide.
- NUNCA criar arquivos/features que o usuário não pediu (sem docs extra, sem READMEs, sem scripts utilitários "úteis").
- NUNCA editar vários domínios (ex: agenda + financeiro + auth) num mesmo commit sem alinhar antes.
- SEMPRE verificar se componente/hook/util/type já existe antes de criar novo. Reusar > duplicar.
- NUNCA implementar pela metade. Se faltar contexto, perguntar ao usuário.
- SEMPRE comunicar em PT-BR, inclusive mensagens de UI, validação, erro, commits e JSDoc.
- Detalhes: [`.claude/rules/meta-regras.md`](.claude/rules/meta-regras.md).

## 2. PADRÕES DE CÓDIGO

- **Stack fixa:** Next.js 16 (App Router) + React 19 + TypeScript estrito + Tailwind 4. NUNCA trocar por CRA, Pages Router ou CSS-in-JS.
- **Arquivos:** máx **300 linhas** por arquivo; funções máx **50 linhas**; componentes máx **200 linhas**. Acima disso → dividir.
- **TypeScript:** SEMPRE `strict: true`. NUNCA usar `any`. Use `unknown` + narrowing, ou tipos gerados do Supabase (`src/types/database.ts`).
- **Naming:** componentes `PascalCase.tsx`, hooks `useXxx.ts`, utils `camelCase.ts`, types `PascalCase`, tabelas Postgres `snake_case_plural`.
- **React:** Server Components por padrão. `"use client"` só quando precisar de estado/efeitos/eventos. NUNCA buscar dados sensíveis no client.
- **Imports:** alias `@/` para `src/`. NUNCA usar relativo profundo (`../../../`).
- **JSDoc:** obrigatório em funções exportadas, hooks e componentes públicos, em PT-BR, explicando POR QUE (não o quê óbvio).
- **Formatação:** Prettier + ESLint + typecheck obrigatórios antes de commit.
- Detalhes: [`.claude/rules/codigo.md`](.claude/rules/codigo.md).

## 3. ARQUITETURA MULTI-TENANT

- **Tenant = estabelecimento** (salão, barbearia, autônomo). Chave primária: `tenants.id` (uuid) + `tenants.slug` (único).
- SEMPRE incluir coluna `tenant_id uuid NOT NULL REFERENCES tenants(id)` em TODA tabela de domínio.
- SEMPRE ativar `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` e criar policy de isolamento por `tenant_id` em TODA nova tabela.
- SEMPRE criar índice composto começando por `tenant_id` (ex: `idx_X_tenant_date` em `(tenant_id, date)`).
- NUNCA fazer query sem filtro por tenant no client — mesmo que RLS filtre, o index perde eficiência.
- NUNCA criar feature "só para o tenant X". Features são padrões replicáveis. Configuração por tenant vai em `tenants.settings jsonb`.
- **Resolução de tenant:** pública via `slug` na URL (`/[slug]`); autenticada via `tenant_id` no JWT claim do usuário logado.
- **Página pública** (`/[slug]`): SSG/ISR, leitura anônima filtrada por policy de `slug`.
- **Painel admin** (`/admin`): SPA com auth obrigatório, JWT resolve `tenant_id`.
- Detalhes + exemplos de queries e policies: [`.claude/rules/multi-tenant.md`](.claude/rules/multi-tenant.md).

## 4. REGRAS DE NEGÓCIO

**Roles:** `owner` (dono), `manager` (gerente), `professional` (profissional). `owner` = acesso total; `manager` = tudo exceto billing/plan; `professional` = só sua agenda/clientes.

**Fases (NUNCA pular):**
- **MVP (Fase 1):** agenda, serviços, profissionais, clientes, página pública `/[slug]`, auth multi-tenant.
- **V2:** financeiro, notificações (WhatsApp/Email), dashboard avançado, configurações.
- **V3:** pagamento online (Stripe/Pagar.me split), marketing, PWA, multi-unidade.

**Regras de agendamento:**
- NUNCA permitir overlap de horário no mesmo `professional_id` + `date` + intervalo `[start_time, end_time)`.
- SEMPRE calcular `end_time` a partir de `service.duration_min` (ou `professional_services.custom_duration` se existir).
- SEMPRE validar `blocked_times` e `professionals.work_schedule` antes de ofertar horário disponível.
- Status válidos: `pending | confirmed | completed | cancelled | noshow`. Transições controladas (não pular de `pending` direto para `completed`).
- NUNCA deletar agendamento — marcar `cancelled` (histórico/auditoria).

**Página pública:**
- URL: `dunee.com.br/[slug-do-salao]`. SSG/ISR. Cliente final NÃO tem login. Cadastro do cliente é automático no 1º agendamento (dedup por `tenant_id + phone`).
- Fluxo fixo: serviço → profissional → data/hora → dados do cliente → confirmação.

**Cliente (tabela `clients`):** escopo por `tenant_id`. Mesmo telefone em tenants diferentes = clientes diferentes. NUNCA compartilhar base de clientes entre tenants.

**Financeiro (V2):** `transactions.type` ∈ `income | expense | commission`. Comissão calculada automaticamente ao completar `appointment` com base em `professionals.commission_pct`.

- Detalhes por módulo: [`.claude/rules/modulos.md`](.claude/rules/modulos.md).

## 5. SEGURANÇA (OBRIGATÓRIO)

- NUNCA commitar `.env*`, chaves Supabase, tokens WhatsApp/Stripe. `.env.local` sempre no `.gitignore`.
- NUNCA expor `SUPABASE_SERVICE_ROLE_KEY` no client. Essa key SÓ em Route Handlers/Server Actions/Edge Functions.
- SEMPRE usar `createClient` correto: `lib/supabase/client.ts` (browser, anon key), `lib/supabase/server.ts` (SSR, cookies), `lib/supabase/admin.ts` (service role, server-only).
- SEMPRE habilitar RLS em toda tabela nova. SEM RLS = vazamento cross-tenant. NUNCA usar `service_role` para bypassar policy no client.
- SEMPRE validar input no servidor com **Zod** (Route Handlers, Server Actions). NUNCA confiar em validação client-only.
- SEMPRE usar Next.js Middleware para auth check no edge antes de `/admin/*`.
- SEMPRE tokenizar pagamento via Stripe/Pagar.me. NUNCA armazenar PAN, CVV ou dados de cartão no banco.
- SEMPRE aplicar rate limit na API pública de agendamento + captcha (hCaptcha) no formulário.
- Dados sensíveis (telefone, email, CPF do cliente final) só leem quem tem permissão no tenant. Logs NUNCA imprimem esses campos em texto claro.
- Dependências: SEMPRE `npm audit` antes de deploy; NUNCA instalar pacote sem verificar origem/manutenção.
- Detalhes + exemplos de RLS, Zod, middleware: [`.claude/rules/seguranca.md`](.claude/rules/seguranca.md).

## 6. PERFORMANCE

- **Página pública** (`/[slug]`): SEMPRE SSG ou ISR (`revalidate` ≤ 60s). Meta: **<1s** de carregamento no 4G. NUNCA fazer CSR na LP pública.
- **Painel admin:** prefetch de dados via Server Components; Client Components só para interação.
- SEMPRE usar índices compostos (`tenant_id, ...`) em queries frequentes; ver `conceito.html` seção "Índices Críticos".
- SEMPRE usar `next/image` com `fetchPriority="high"` em LCP e `loading="lazy"` abaixo da dobra.
- SEMPRE habilitar connection pooling (PgBouncer transaction mode) no Supabase.
- NUNCA fazer N+1: use join (`select('*, professionals(*)')`) ou RPC.
- NUNCA buscar toda a tabela: paginar (`range()`), filtrar no servidor, limitar payload.
- Cache de leituras frequentes (serviços, profissionais) via `cache()` / `unstable_cache` do Next ou Supabase edge cache.
- NUNCA carregar biblioteca pesada no bundle público; use `next/dynamic` com `ssr:false` quando aplicável.

## 7. VERIFICAÇÃO PÓS-IMPLEMENTAÇÃO

Ao final de QUALQUER entrega, rodar o checklist correspondente ao domínio tocado antes de commitar. Detalhes: [`.claude/rules/checklist.md`](.claude/rules/checklist.md).

Mínimo sempre: `tsc --noEmit` ✅, `eslint` ✅, `prettier --check` ✅, build local ✅, RLS testada ✅, PT-BR ✅.

**Validador automático no pre-commit:** `scripts/validate-rules.sh` roda via `.githooks/pre-commit` e bloqueia commit ao detectar: `any`, `<img>`, `Math.random`, formatação manual de moeda/data, `catch` vazio, segredo hardcoded, `SERVICE_ROLE` fora de server-only, `NEXT_PUBLIC_*SECRET`, código específico de tenant, URL `.vercel.app`, tabela sem `tenant_id`, migration sem RLS/policy. Ativar em cada clone com: `git config core.hooksPath .githooks`.

## 8. ANTI-PATTERNS PROIBIDOS

- ❌ Tabela sem `tenant_id` + RLS.
- ❌ Query no client sem filtro por tenant (dependendo só de RLS).
- ❌ `service_role` key chegando no bundle do browser.
- ❌ `any` em TypeScript, `@ts-ignore`, `@ts-expect-error` sem justificativa em comentário.
- ❌ Hardcode de slug, tenant, URL `*.vercel.app` no código de produção.
- ❌ Lógica de negócio crítica (disponibilidade, comissão, cancelamento) somente no client.
- ❌ Deletar `appointment` ou `client` (usar soft delete / status).
- ❌ Comentários/UI/commits em inglês.
- ❌ Arquivo >300 linhas, função >50 linhas, componente >200 linhas sem dividir.
- ❌ Buscar dados de outro tenant via `admin` client para "conveniência".
- ❌ Criar módulo/feature específico para um único salão.
- ❌ Guardar senha em plaintext, armazenar token de terceiros sem criptografia em repouso.
- ❌ Commit com `--no-verify`.

## 9. REGRAS ABSOLUTAS (NUNCA ALTERAR)

- **Git/GitHub:** NUNCA push sem `gh auth switch` para conta `ViniciusMolinari` (hook de SessionStart cuida, mas confirmar). Repo = `ViniciusMolinari/dunee001`.
- **Commits:** PT-BR, imperativo, escopo primeiro. Ex: `feat(agenda): calcula fim do slot pelo duration do serviço`. NUNCA `--no-verify`. SEMPRE criar commit novo ao invés de amend publicado.
- **PRs:** base = `main`. Descrição em PT-BR com **Contexto / Mudanças / Como testar / Checklist de segurança e multi-tenant**.
- **Branches:** `feat/xxx`, `fix/xxx`, `chore/xxx`, `refactor/xxx`. NUNCA trabalhar direto em `main`.
- **Ações destrutivas** (drop table, truncate, reset migration, force push, `rm -rf`): SEMPRE confirmar com o usuário ANTES.
- **Migrations Supabase:** SEMPRE versionadas em `supabase/migrations/`, com rollback quando possível. NUNCA editar migration já aplicada em produção — criar nova.
- **Deploy:** Vercel para frontend/API, Supabase para banco/auth/storage. NUNCA misturar com Firebase.
- **Domínio:** produção em `dunee.com.br`. Subdomínios `*.vercel.app` são provisórios — NUNCA referenciar em código, config ou copy.
- **Idioma:** PT-BR em TODA saída: UI, erros, commits, PRs, JSDoc, migration comments.
- **Comunicação com o usuário:** PT-BR, objetiva, apresentando trade-offs e pedindo decisão.

## 10. IDENTIDADE VISUAL

**Design system: "Atelier Lumière — Apple-inspired" (light theme).**
Fonte canônica: `src/app/globals.css` (CSS vars) + `tailwind.config.ts`. NUNCA hardcodar hex em componente.

**Paleta (valores em HSL, como no shadcn — nunca usar hex direto em JSX):**

| Token | Valor HSL | Aproximação | Uso |
|-------|-----------|-------------|-----|
| `--background` | `0 0% 100%` | `#ffffff` | Fundo principal |
| `--foreground` | `0 0% 7%` | `#121212` | Texto principal |
| `--card` | `0 0% 100%` | `#ffffff` | Surfaces |
| `--card-foreground` | `0 0% 7%` | `#121212` | Texto em cards |
| `--primary` | `0 0% 7%` | `#121212` | Botões primários (preto Apple-like) |
| `--primary-foreground` | `0 0% 100%` | `#ffffff` | Texto sobre primary |
| `--secondary` | `220 14% 96%` | `#f1f3f5` | Superfícies sutis |
| `--secondary-foreground` | `0 0% 7%` | `#121212` | — |
| `--muted` | `220 14% 96%` | `#f1f3f5` | Backgrounds de apoio |
| `--muted-foreground` | `220 9% 46%` | `#6b7280` | Texto secundário |
| `--accent` | `211 100% 50%` | `#007aff` | CTAs / links (iOS blue) |
| `--accent-foreground` | `0 0% 100%` | `#ffffff` | Texto sobre accent |
| `--destructive` | `0 72% 50%` | `#dc2626` | Erros, cancelamento, no-show |
| `--destructive-foreground` | `0 0% 100%` | `#ffffff` | — |
| `--border` | `220 13% 91%` | `#e5e7eb` | Bordas padrão |
| `--input` | `220 13% 91%` | `#e5e7eb` | Bordas de inputs |
| `--ring` | `0 0% 7%` | `#121212` | Focus ring |
| `--surface` | `0 0% 98%` | `#fafafa` | Seção alternativa |
| `--surface-elevated` | `0 0% 100%` | `#ffffff` | Cards elevados |
| `--hairline` | `220 13% 88%` | `#dcdfe4` | Divisores finos |

Sidebar (painel `/admin`) tem variantes próprias: `--sidebar-background`, `--sidebar-foreground`, `--sidebar-primary`, `--sidebar-accent`, `--sidebar-border`, `--sidebar-ring`. Ver `globals.css`.

**Gradients e sombras:**
- `--gradient-fade: linear-gradient(180deg, hsl(0 0% 100%) 0%, hsl(220 14% 96%) 100%)`
- `--gradient-hero: radial-gradient(ellipse at center top, hsl(220 14% 98%) 0%, hsl(0 0% 100%) 60%)`
- `--shadow-soft: 0 1px 2px hsl(0 0% 0% / 0.04), 0 4px 12px hsl(0 0% 0% / 0.04)`
- `--shadow-elevated: 0 12px 40px -12px hsl(0 0% 0% / 0.12)`

**Geometria:**
- `--radius: 1.25rem` (20px, bem arredondado). `lg = var(--radius)`, `md = calc(radius - 2px)`, `sm = calc(radius - 4px)`.
- Botão pill helper: classe `.btn-pill` em `globals.css` (rounded-full, padding `0.7rem 1.25rem`).

**Transições:**
- `--transition-smooth: cubic-bezier(0.22, 1, 0.36, 1)`
- `--transition-spring: cubic-bezier(0.34, 1.56, 0.64, 1)`

**Tipografia:**
- Fonte única: **Inter** (Google Fonts, pesos 300/400/500/600/700/800). Usar `next/font/google` para self-host.
- `letter-spacing` global: `-0.011em` (body). Títulos `h1–h4`: weight 600, `letter-spacing -0.035em`, `line-height 1.05`.
- Classe `.font-display` disponível em `globals.css`.
- `font-feature-settings: 'cv11', 'ss01', 'ss03'` para aparência SF-like.
- `.text-balance { text-wrap: balance }` para títulos.

**Glass nav (topbar):**
- Classe `.glass-nav`: `background: hsla(0,0%,100%,0.72); backdrop-filter: saturate(180%) blur(20px)`.

**Tema padrão: LIGHT.** Dark mode NÃO está no MVP. Quando/se entrar, segue a convenção shadcn (`.dark { ... }` sobrescrevendo as vars). NUNCA usar `dark:` prefix em utilidades sem alinhar.

**Logo:** `dunee-logo.png` (já existe em `src/assets/` do Lovable e será portado para `public/dunee-logo.png` no projeto Next.js). Wordmark "Dunee" em Inter weight 700/800, `letter-spacing -0.04em`, cor `--foreground`.

**Componentes base:** 49 componentes `shadcn/ui` herdados do Lovable (`src/components/ui/*`). NUNCA reimplementar do zero — estender. Adições que NÃO existem no shadcn ficam em `src/components/[domínio]/`.

**Regras duras:**
- NUNCA hex/rgb inline em JSX — sempre token (`bg-primary`, `text-muted-foreground`, `border-border`).
- NUNCA mudar a paleta sem alinhar com o usuário.
- NUNCA misturar convenções: se uma tela usa shadcn tokens, a tela inteira usa.
- Contraste AA mínimo em texto (checar `muted-foreground` sobre `muted` em textos importantes).

---

## 📁 Estrutura de Pastas (alvo)

```
dunee001/
├── src/
│   ├── app/
│   │   ├── layout.tsx               # Root layout (fonts, providers)
│   │   ├── page.tsx                 # LP dunee.com.br
│   │   ├── [slug]/                  # Página pública do tenant (SSG/ISR)
│   │   │   ├── page.tsx
│   │   │   └── agendar/page.tsx
│   │   ├── admin/                   # Painel (auth obrigatório)
│   │   │   ├── layout.tsx           # Sidebar + auth guard
│   │   │   ├── page.tsx             # Dashboard
│   │   │   ├── agenda/page.tsx
│   │   │   ├── clientes/page.tsx
│   │   │   ├── profissionais/page.tsx
│   │   │   ├── servicos/page.tsx
│   │   │   ├── financeiro/page.tsx
│   │   │   └── configuracoes/page.tsx
│   │   ├── auth/
│   │   │   ├── login/page.tsx
│   │   │   ├── register/page.tsx
│   │   │   └── callback/route.ts
│   │   └── api/
│   │       ├── appointments/route.ts
│   │       ├── availability/route.ts
│   │       └── webhooks/whatsapp/route.ts
│   ├── components/
│   │   ├── ui/                      # Base (Button, Input, Modal…)
│   │   ├── admin/                   # Painel
│   │   └── booking/                 # Fluxo público
│   ├── lib/
│   │   ├── supabase/{client,server,admin}.ts
│   │   ├── utils.ts
│   │   └── constants.ts
│   ├── hooks/{useAuth,useTenant,useAppointments}.ts
│   └── types/database.ts            # Gerado via supabase gen types
├── supabase/
│   ├── migrations/*.sql
│   └── seed.sql
├── .env.local                       # NUNCA commitar
└── package.json
```

---

## 📚 Pointers rápidos

- Como estender este sistema de regras → [`.claude/rules/meta-regras.md`](.claude/rules/meta-regras.md)
- Padrões de código detalhados → [`.claude/rules/codigo.md`](.claude/rules/codigo.md)
- Multi-tenant / RLS / Supabase → [`.claude/rules/multi-tenant.md`](.claude/rules/multi-tenant.md)
- Segurança (RLS, env, Zod, middleware) → [`.claude/rules/seguranca.md`](.claude/rules/seguranca.md)
- Regras por módulo → [`.claude/rules/modulos.md`](.claude/rules/modulos.md)
- Checklists pós-implementação → [`.claude/rules/checklist.md`](.claude/rules/checklist.md)
