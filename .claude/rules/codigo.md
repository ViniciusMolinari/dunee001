# Código — Padrões detalhados

## 1. Stack e versões travadas

| Camada | Ferramenta | Versão-alvo |
|--------|-----------|------------|
| Framework | Next.js (App Router) | 16.x |
| UI | React | 19.x |
| Linguagem | TypeScript | 5.x estrito |
| Estilo | Tailwind CSS | 4.x |
| Backend-as-a-Service | Supabase JS | última estável |
| Validação | Zod | última estável |
| Lint | ESLint + `eslint-config-next` | compatível |
| Formatação | Prettier | última estável |
| Teste | Vitest + Testing Library | (V2) |

**Proibido:** Pages Router, Create React App, Redux tradicional, CSS-in-JS (styled-components/emotion), Material UI, jQuery, Moment (usar `date-fns` ou Intl).

## 2. Limites de tamanho

| Artefato | Máximo |
|---------|--------|
| Arquivo `.ts` / `.tsx` | **300 linhas** |
| Função | **50 linhas** |
| Componente React | **200 linhas** |
| Parâmetros de função | **4** (acima → objeto `params`) |
| Aninhamento (`if`/`for`) | **3 níveis** |

Acima → dividir em subcomponente, subhook ou util. Se não conseguir dividir, explique em JSDoc por quê.

## 3. TypeScript

- `tsconfig.json`: `strict: true`, `noUncheckedIndexedAccess: true`, `noImplicitOverride: true`.
- NUNCA `any`. NUNCA `@ts-ignore`. `@ts-expect-error` só com comentário justificando + data.
- Tipos de banco: gerados por `npx supabase gen types typescript --project-id <id> > src/types/database.ts`. Consumir via `Database['public']['Tables']['appointments']['Row']`.
- Preferir `type` para unions/aliases e `interface` para contratos de componente/props.
- Nomes: `UserRole`, `AppointmentStatus`, `CreateAppointmentInput` — não `IUserRole`, não `TUserRole`.
- Retornos explícitos em funções exportadas.

Exemplo:
```ts
import type { Database } from "@/types/database";

type Appointment = Database["public"]["Tables"]["appointments"]["Row"];

export function isCancelable(appt: Appointment): boolean {
  return appt.status === "pending" || appt.status === "confirmed";
}
```

## 4. React / Next.js

- **Server Components por padrão.** `"use client"` SOMENTE quando houver: estado local, efeitos, event handlers, APIs de browser, contexto de cliente.
- Busca de dados: Server Components + Supabase server client OU Server Actions. NUNCA `fetch` direto no client para endpoint que expõe service role.
- **Suspense + streaming** para listas longas e dashboards.
- **Mutations:** Server Actions (`"use server"`) com validação Zod. Fallback: Route Handlers em `/api/*`.
- **Forms:** `react-hook-form` + Zod resolver. Mensagens em PT-BR.
- Estado global pequeno: Context. Estado global complexo: **Zustand** (preferido a Redux).
- NUNCA usar `useEffect` para sincronizar prop → estado. Deriva no render.
- `next/image` para TODA imagem. `next/font` para tipografia. `next/dynamic` para lib pesada condicional.

## 5. Nomenclatura

| Artefato | Padrão | Exemplo |
|---------|--------|---------|
| Componente React | `PascalCase.tsx` | `AppointmentCard.tsx` |
| Hook | `useXxx.ts` | `useTenant.ts` |
| Util | `camelCase.ts` | `formatCurrency.ts` |
| Type/Interface | `PascalCase` | `AppointmentStatus` |
| Constante | `SCREAMING_SNAKE` | `MAX_BOOKING_DAYS` |
| Variável/função | `camelCase` | `getAvailableSlots` |
| Tabela Postgres | `snake_case_plural` | `appointments`, `blocked_times` |
| Coluna Postgres | `snake_case` | `start_time`, `tenant_id` |
| Enum Postgres | `snake_case_singular` | `appointment_status` |
| Rota Next | `kebab-case` | `/admin/configuracoes` |
| Branch Git | `tipo/kebab-case` | `feat/agenda-bloqueios` |

## 6. Organização de imports

Ordem (separar com linha em branco):
1. Externos (`react`, `next/*`, `@supabase/*`)
2. Internos via alias `@/` (components, lib, hooks, types)
3. Relativos (`./`, `../`) — evitar fundo (`../../../`)
4. Tipos (`import type ...`) no fim do seu grupo

Alias obrigatório em `tsconfig.json`:
```json
{ "paths": { "@/*": ["./src/*"] } }
```

## 7. JSDoc (PT-BR)

Obrigatório em funções exportadas, hooks e componentes públicos. Explicar o **porquê** ou restrições não óbvias, não o **o quê**.

```ts
/**
 * Retorna os slots livres para um profissional numa data, considerando
 * work_schedule, blocked_times e appointments não cancelados.
 *
 * @remarks
 * Fonte única de verdade para disponibilidade — usar esta função tanto
 * na página pública quanto no painel. NUNCA recalcular inline.
 */
export async function getAvailableSlots(
  tenantId: string,
  professionalId: string,
  date: string,
): Promise<TimeSlot[]> { /* ... */ }
```

Regras:
- Sem comentários óbvios (`// incrementa o contador`).
- Comentário explica constraint, invariante ou motivo. Remover se vira ruído.
- Nomes ruins > comentários — renomeie antes de comentar.

## 8. Tratamento de erros

- Fronteira do sistema (Route Handler, Server Action): capturar, logar com contexto (sem PII em texto claro), devolver resposta padronizada `{ ok: false, code, message }` em PT-BR.
- Código interno: deixar subir. NUNCA `try/catch` para silenciar.
- UI: `error.tsx` por rota. Mensagem amigável em PT-BR + botão "tentar novamente".

## 9. Tailwind

- Use tokens shadcn (`bg-primary`, `text-muted-foreground`, `border-border`, `bg-accent`) definidos em `tailwind.config.ts` + CSS vars em `globals.css`. NUNCA `bg-[#007aff]` ou `text-[hsl(...)]` inline.
- Ordenar classes: layout → espaçamento → tipografia → cor → estado (`hover:*`, `focus:*`) → responsivo (`md:*`).
- Componentizar padrões repetidos (Button, Input). NUNCA copiar 15 classes em vários lugares.
- `cn()` helper (clsx + tailwind-merge) para classes condicionais.

## 10. Commits (Conventional, PT-BR)

Formato: `tipo(escopo): descrição em imperativo`.

Tipos: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `build`, `ci`, `style`.

Exemplos:
- `feat(agenda): calcula end_time a partir de duration do serviço`
- `fix(auth): redireciona /admin para /login quando JWT expirado`
- `chore(supabase): adiciona índice composto em appointments (tenant, date)`

Regras: uma intenção por commit. Se precisar de `e`/`também`, são dois commits. NUNCA `--no-verify`. NUNCA amend em commit já publicado.

## 11. Scripts obrigatórios (package.json)

```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "db:types": "supabase gen types typescript --linked > src/types/database.ts"
  }
}
```

Antes de commitar (sempre): `npm run typecheck && npm run lint && npm run format:check`.
