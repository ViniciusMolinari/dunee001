# Multi-Tenant — Arquitetura detalhada

> O Dunee é um SaaS B2B onde cada **tenant** é um estabelecimento (salão, barbearia ou profissional autônomo). Isolamento lógico via `tenant_id` + RLS no Postgres. NUNCA criar código específico por tenant.

## 1. Modelo conceitual

- **Banco compartilhado (shared database).** Todos os tenants no mesmo Postgres da Supabase.
- **Coluna `tenant_id uuid NOT NULL`** em TODAS as tabelas de domínio.
- **Row Level Security (RLS) ativa em TODAS as tabelas.** Linha de defesa final — se houver bug no código, o banco recusa.
- **Resolução de tenant:**
  - **Área autenticada:** `tenant_id` vem do JWT do usuário (coluna `users.tenant_id`).
  - **Página pública:** `tenant_id` resolvido pelo `slug` da URL (`tenants.slug` único).

## 2. Tabelas-base (schema do MVP)

| Tabela | Coluna `tenant_id`? | Observação |
|--------|--------------------|-----------|
| `tenants` | — (é o próprio tenant) | `id`, `slug`, `plan`, `settings jsonb` |
| `users` | ✅ FK → `tenants` | role = `owner \| manager \| professional` |
| `professionals` | ✅ | `commission_pct`, `work_schedule jsonb` |
| `services` | ✅ | `duration_min`, `price` |
| `professional_services` (N:N) | — (herda via FKs) | `custom_price`, `custom_duration` |
| `clients` | ✅ | dedup por `(tenant_id, phone)` |
| `appointments` | ✅ | status enum, FKs para client/pro/service |
| `transactions` | ✅ | `type` ∈ income/expense/commission |
| `blocked_times` | ✅ | folga/feriado do profissional |

**Regra:** ao criar tabela nova de domínio, ela SEMPRE nasce com `tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`.

## 3. Padrão RLS (copiar e adaptar)

Toda tabela nova:

```sql
ALTER TABLE <tabela> ENABLE ROW LEVEL SECURITY;

-- Isolamento por tenant: usuário autenticado só vê linhas do seu tenant
CREATE POLICY "tenant_isolation_select" ON <tabela>
  FOR SELECT USING (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
  );

CREATE POLICY "tenant_isolation_insert" ON <tabela>
  FOR INSERT WITH CHECK (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
  );

CREATE POLICY "tenant_isolation_update" ON <tabela>
  FOR UPDATE USING (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
  );

CREATE POLICY "tenant_isolation_delete" ON <tabela>
  FOR DELETE USING (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
  );
```

### Policy por role (exemplo)

```sql
-- profissional só vê os próprios agendamentos; owner/manager veem tudo do tenant
CREATE POLICY "appointments_role_scope" ON appointments
  FOR SELECT USING (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
    AND (
      (SELECT role FROM users WHERE id = auth.uid()) IN ('owner','manager')
      OR professional_id = (SELECT id FROM professionals WHERE user_id = auth.uid())
    )
  );
```

### Leitura pública pelo slug (LP do salão)

```sql
-- services visíveis para anônimos, mas apenas do tenant cujo slug está na URL
CREATE POLICY "services_public_read" ON services
  FOR SELECT TO anon USING (
    active = true
    AND tenant_id IN (
      SELECT id FROM tenants
      WHERE slug = current_setting('request.jwt.claims', true)::jsonb->>'slug'
    )
  );
```

Ou definir a variável via RPC/Edge Function antes do SELECT:
```sql
SELECT set_config('app.current_slug', '<slug>', true);
```

## 4. Queries — sempre filtrar por tenant

Mesmo com RLS ativa, filtre explicitamente por `tenant_id` para:
1. Usar o índice composto `(tenant_id, ...)`.
2. Deixar a intenção clara no código.
3. Funcionar em contexto `service_role` (onde RLS é bypassed).

```ts
// ✅ correto
const { data } = await supabase
  .from("appointments")
  .select("*, professionals(*), services(*), clients(*)")
  .eq("tenant_id", tenantId)
  .eq("date", date)
  .order("start_time");

// ❌ errado — depende só de RLS, perde índice
const { data } = await supabase.from("appointments").select("*").eq("date", date);
```

## 5. Índices obrigatórios

Toda tabela com `tenant_id` ganha ÍNDICE COMPOSTO começando por `tenant_id`. Exemplos do MVP:

```sql
CREATE INDEX idx_appointments_tenant_prof_date
  ON appointments (tenant_id, professional_id, date);

CREATE INDEX idx_appointments_tenant_date_status
  ON appointments (tenant_id, date, status)
  WHERE status <> 'cancelled';

CREATE UNIQUE INDEX idx_tenants_slug ON tenants (slug);

CREATE INDEX idx_clients_tenant_phone ON clients (tenant_id, phone);

CREATE INDEX idx_transactions_tenant_date
  ON transactions (tenant_id, date DESC);

CREATE INDEX idx_blocked_times_tenant_prof_date
  ON blocked_times (tenant_id, professional_id, date);
```

## 6. Resolução de tenant no app

### Usuário autenticado (painel)
```ts
// src/hooks/useTenant.ts
export async function getCurrentTenantId(supabase: SupabaseClient) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Não autenticado");
  const { data } = await supabase
    .from("users")
    .select("tenant_id, role")
    .eq("id", user.id)
    .single();
  return data; // { tenant_id, role }
}
```

### Página pública (por slug)
```ts
// src/app/[slug]/page.tsx  (Server Component)
export default async function Page({ params }: { params: { slug: string } }) {
  const supabase = createServerClient();
  const { data: tenant } = await supabase
    .from("tenants")
    .select("id, name, logo_url, working_hours, settings")
    .eq("slug", params.slug)
    .single();
  if (!tenant) notFound();
  // carregar services/professionals filtrando por tenant.id
}
```

## 7. Como replicar uma feature para TODOS os tenants

Quando o usuário pedir "módulo de estoque", "programa de fidelidade" etc.:

1. Criar migração com tabela nova contendo `tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE`.
2. Ativar RLS + 4 policies (select/insert/update/delete).
3. Criar índice composto `(tenant_id, ...)`.
4. Adicionar rota em `app/admin/<modulo>/page.tsx` que lê `tenant_id` do usuário e já filtra.
5. Atualizar `modulos.md` e o menu da sidebar.
6. Atualizar `types/database.ts` (rodar `npm run db:types`).

Qualquer tenant novo (ou já existente) ganha o módulo automaticamente no próximo acesso.

## 8. Armadilhas conhecidas (NUNCA fazer)

- ❌ Criar tabela sem `tenant_id`. Exceção: `tenants` (é ele próprio) e tabelas de lookup global (ex: `countries`).
- ❌ Usar `service_role` key no frontend/Edge público "só pra testar".
- ❌ Query sem `.eq("tenant_id", tenantId)` confiando 100% na RLS.
- ❌ Index que não começa por `tenant_id` em tabela de tenant (perde seletividade).
- ❌ Deletar tenant com `DELETE FROM tenants WHERE id=...` sem `ON DELETE CASCADE` configurado nas FKs.
- ❌ Copiar dados de tenant-A para tenant-B em "migração manual" via SQL ad-hoc. Qualquer migração de dados passa por código revisado.
- ❌ `tenant.settings` virando "código de feature-flag" — settings é configuração, não lógica condicional que muda o comportamento do produto por cliente.

## 9. Planos e limites por tenant

`tenants.plan` ∈ `free | pro | business`. Diferenças aplicadas via **middleware de domínio** (não por código espalhado):

- `free`: 1 profissional, agendamento online, página pública.
- `pro`: múltiplos profissionais, financeiro, notificações WhatsApp.
- `business`: multi-unidade (V3), split payment, domínio próprio.

Checagem centralizada em `lib/plan.ts`:
```ts
export function assertFeature(plan: Plan, feature: Feature) {
  if (!FEATURES_BY_PLAN[plan].includes(feature)) {
    throw new PlanFeatureError(feature);
  }
}
```
Chamar no Server Action / Route Handler antes da mutação. NUNCA decidir pelo client.
