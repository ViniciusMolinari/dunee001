# Módulos — Regras por domínio

> Toda feature aqui descrita é **multi-tenant por construção**. Ao ler "ao criar agendamento", entenda "ao criar agendamento de um tenant qualquer".

## MVP — Fase 1

### 1. Agenda & Agendamento (`appointments`, `blocked_times`)

**Regras de negócio:**
- Status: `pending | confirmed | completed | cancelled | noshow`.
- Transições válidas:
  - `pending → confirmed | cancelled`
  - `confirmed → completed | cancelled | noshow`
  - `completed | cancelled | noshow` → terminal (NUNCA reativar; criar agendamento novo).
- NUNCA permitir overlap: mesmo `professional_id`, mesma `date`, intervalos `[start_time, end_time)` que se cruzam.
- `end_time = start_time + (professional_services.custom_duration ?? services.duration_min)`.
- Validar contra `blocked_times` e `professionals.work_schedule`.
- Antecedência mínima/máxima configurável em `tenants.settings.booking`.
- NUNCA deletar — status `cancelled` é o soft delete.

**UI:**
- Visualizações: dia, semana, mês. Filtro por profissional (ou "todos").
- Cores do evento por categoria de serviço (Cabelo, Barba, Unha, Estética) — tokens Tailwind, NUNCA hex inline.
- Drag-and-drop (V2) para reagendar respeitando validações no servidor.

**Disponibilidade:** **uma única função** `getAvailableSlots(tenantId, professionalId, date)` em `src/lib/availability.ts`. LP pública E painel consomem a mesma função. NUNCA duplicar regra em dois lugares.

### 2. Serviços (`services`, `professional_services`)

- Categorias padrão: `Cabelo | Barba | Unha | Estética | Sobrancelha | Outros`. Customizáveis via `tenants.settings.service_categories` (array).
- `price` em `numeric(10,2)`; SEMPRE em reais. NUNCA guardar centavos como inteiro (não temos pagamento online no MVP — mudar SÓ quando entrar Stripe).
- Sobrescrita por profissional: `professional_services.custom_price` e `custom_duration` (ambos nullable → herdam do serviço).
- Campo `active`: desativar > deletar. Agendamentos passados continuam válidos.

### 3. Profissionais (`professionals`)

- 1 profissional ↔ 1 `users` (role `professional`) via `user_id`. Dono/gerente não precisa ter profissional vinculado se não atende.
- `work_schedule jsonb` (padrão):
  ```json
  { "mon": [["09:00","18:00"]], "tue": [["09:00","12:00"],["13:00","18:00"]], "wed": [], ... }
  ```
- `commission_pct` ∈ `[0, 100]`. Usado no cálculo automático de `transactions.type='commission'` ao concluir agendamento (V2).
- Fotos: Supabase Storage bucket `avatars`, policy por `tenant_id`.

### 4. Clientes (`clients`)

- Chave de dedup: `(tenant_id, phone)`. Mesmo telefone em tenants diferentes = clientes diferentes (NUNCA cruzar).
- Cadastro automático no 1º agendamento público (fluxo do `[slug]/agendar`).
- `tags text[]` padrão: `VIP | Frequente | Novo | Inativo`. Customizáveis.
- `total_visits`, `total_spent` atualizados por trigger ou job; NUNCA calcular no client.
- Anonimização LGPD: ver [`seguranca.md`](./seguranca.md).

### 5. Página Pública (`/[slug]`)

- SSG/ISR (`export const revalidate = 60`). Alvo < 1s no 4G.
- Single-page: hero + serviços + agendamento INLINE (sem navegação entre páginas).
- Fluxo fixo: **serviço → profissional → data/hora → dados do cliente → confirmação**.
- Cliente final NÃO tem login nem senha.
- Captcha (hCaptcha) na confirmação + rate limit.
- URL canônica: `https://dunee.com.br/[slug]`. NUNCA expor `vercel.app`.
- Meta SEO: `og:image` gerada do logo + nome do salão; `<title>` = `{tenant.name} — Agendamento online | Dunee`.
- Schema.org `LocalBusiness` + `Service`.

### 6. Auth & Multi-tenancy

- Supabase Auth (email + senha). Google OAuth em V2.
- Fluxos:
  - **Signup do tenant (dono):** `/auth/register` cria `auth.user` + linha em `users` (role `owner`) + linha em `tenants`.
  - **Convite de profissional:** owner/manager envia convite por email → link cria `auth.user` + `users` (role `professional`) no mesmo `tenant_id`.
  - **Reset senha:** Supabase magic link.
- JWT traz `sub` (user_id); `tenant_id` + `role` são buscados de `users` em cada request (cache no Server Component).
- NUNCA expor "trocar de tenant" — um usuário = um tenant. Exceção futura: super-admin Dunee (V2+).

## V2 — Crescimento

### 7. Financeiro (`transactions`)

- Tipos: `income | expense | commission`.
- `income` criado automaticamente ao marcar `appointment.status = completed`, com `amount = appointment.price`.
- `commission` criada simultaneamente, com `amount = appointment.price * professional.commission_pct / 100`.
- `expense` manual (dono lança).
- Métodos: `pix | card | cash`.
- Relatórios: receita diária/semanal/mensal; ranking profissional; método de pagamento; no-show rate.
- Exportar PDF/Excel (V2.1). NUNCA gerar no client — sempre server-side com PII isolada.

### 8. Notificações

- **WhatsApp Business API** (via Z-API ou Evolution): confirmação na criação + lembrete 24h + lembrete 1h. Templates aprovados.
- **Email (Resend):** confirmação com link cancelar/reagendar + Google Calendar.
- **Painel:** push notif in-app via Supabase Realtime (`appointments` INSERT filtrado por `tenant_id + professional_id`).
- Todos com opt-out por cliente.

### 9. Dashboard Avançado

- Stats: receita hoje/semana/mês, agendamentos do dia, taxa no-show, novos clientes.
- Gráficos: receita por período, horários de pico, ranking profissional.
- Filtros por período e profissional.
- Dados agregados via RPC Postgres (views materializadas se necessário).

### 10. Configurações

- Dados do estabelecimento (nome, slug, endereço, telefone, logo).
- Horário de funcionamento (`tenants.working_hours jsonb`).
- Intervalo mínimo entre agendamentos.
- Política de cancelamento (texto exibido na LP).
- Personalização da LP: cor primária dentro da paleta da marca (não sai da identidade Dunee), banner opcional.

## V3 — Escala

### 11. Pagamento Online
- Stripe/Pagar.me + Pix + split (plataforma + tenant + profissional).
- Cobrança antecipada opcional por serviço (`services.require_prepayment`).

### 12. Marketing
- Campanhas WhatsApp em lote (respeitar política do WhatsApp).
- Cupons de desconto com validade e uso limitado.
- Programa de fidelidade (acúmulo por visita → recompensa).

### 13. PWA
- Service Worker com cache offline da agenda.
- Push notifications via Web Push API.
- Instalável.

### 14. Multi-unidade
- Conceito: `tenant` passa a poder ter `units` (filiais).
- Profissional transferível entre unidades da mesma tenant.
- Dashboard consolidado por unidade + total.
- **Atenção:** quebra algumas queries MVP; planejar migração com cuidado.

## Regras transversais

- Qualquer módulo novo SEGUE o padrão: migration com `tenant_id` + RLS + 4 policies + índice composto + tipos gerados + entrada no sidebar + checagem de plano (`assertFeature`).
- Flag de feature por plano em `lib/plan.ts`. NUNCA `if (tenant.name === 'X')`.
- Copy da UI em PT-BR, tom direto, sem gírias.
