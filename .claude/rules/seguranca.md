# Segurança — Regras detalhadas

> O Dunee lida com dados pessoais de clientes finais (telefone, email, nome), dados financeiros (comissões, receitas) e múltiplos tenants no mesmo banco. Segurança NUNCA é opcional.

## 1. Pilares

1. **Defesa em profundidade:** RLS no banco + validação no servidor + middleware + client. Cada camada falhando ainda deixa as outras segurando.
2. **Menor privilégio:** anon key por padrão; service role SOMENTE em contextos server-only específicos.
3. **Nada sensível no client:** chaves, lógica de plano, cálculo de comissão, regra de disponibilidade.
4. **Log seguro:** nunca PII em texto claro; IDs ok, valores não.

## 2. Chaves e ambiente

`.env.local` (NUNCA commitar):
```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...        # server-only
SUPABASE_JWT_SECRET=...
WHATSAPP_API_TOKEN=...                # server-only
RESEND_API_KEY=...                    # server-only
STRIPE_SECRET_KEY=...                 # server-only
HCAPTCHA_SECRET=...                   # server-only
```

Regras:
- SEMPRE `.env.local`, `.env*.local` no `.gitignore`.
- SEMPRE variáveis server-only SEM prefixo `NEXT_PUBLIC_`.
- SEMPRE validar env na inicialização com Zod (`src/lib/env.ts`).
- NUNCA logar env em stdout/Sentry.

## 3. Três clients Supabase

```ts
// src/lib/supabase/client.ts — uso no BROWSER (anon key)
import { createBrowserClient } from "@supabase/ssr";
export const supabaseBrowser = () =>
  createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
```

```ts
// src/lib/supabase/server.ts — SSR / Server Components / Route Handlers
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
export const supabaseServer = () =>
  createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: cookies() }
  );
```

```ts
// src/lib/supabase/admin.ts — SERVER-ONLY; usa service role
import { createClient } from "@supabase/supabase-js";
import "server-only"; // garante que nunca entra no bundle client
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false } }
);
```

Regras:
- `admin` SÓ em: webhooks, crons, tarefas administrativas do próprio Dunee, operações que precisam contornar RLS com auditoria.
- NUNCA em Server Component que renderiza UI do usuário comum.
- Toda operação com `admin` LOGA quem disparou, quando, qual ação (tabela dedicada `audit_logs` com `tenant_id`, `actor_id`, `action`, `payload_hash`).

## 4. Validação de input (Zod)

Toda borda externa (Server Action, Route Handler, webhook) valida com Zod. Mensagens em PT-BR.

```ts
import { z } from "zod";

export const CreateAppointmentSchema = z.object({
  tenantId: z.string().uuid(),
  clientName: z.string().min(2, "Nome muito curto"),
  clientPhone: z.string().regex(/^\d{10,11}$/, "Telefone inválido"),
  serviceId: z.string().uuid(),
  professionalId: z.string().uuid(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
});

export type CreateAppointmentInput = z.infer<typeof CreateAppointmentSchema>;
```

NUNCA confiar no que chega do client. NUNCA usar `as` para burlar validação.

## 5. Middleware de autenticação

```ts
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";
import { createMiddlewareClient } from "@supabase/ssr";

export async function middleware(req: NextRequest) {
  if (!req.nextUrl.pathname.startsWith("/admin")) return NextResponse.next();

  const res = NextResponse.next();
  const supabase = createMiddlewareClient({ req, res });
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    const login = new URL("/auth/login", req.url);
    login.searchParams.set("redirect", req.nextUrl.pathname);
    return NextResponse.redirect(login);
  }
  return res;
}

export const config = { matcher: ["/admin/:path*"] };
```

## 6. RLS — regras inegociáveis

- SEMPRE ativar RLS em tabela nova ANTES de inserir dados.
- SEMPRE 4 policies (SELECT, INSERT, UPDATE, DELETE) por tabela. Ausência de policy = bloqueio (bom), mas tem que ser explícito no código revisado.
- SEMPRE testar RLS com query de um usuário de outro tenant retornando `0 rows`.
- NUNCA `FORCE RLS OFF` em produção.
- NUNCA ligar policy só para `anon` sem filtro restritivo (apenas LP pública com `active = true` + filtro por slug).
- Ver exemplos em [`multi-tenant.md`](./multi-tenant.md).

## 7. CSRF, CORS, cabeçalhos

- SSR + cookies httpOnly via `@supabase/ssr` → CSRF mitigado pela origem + SameSite.
- Server Actions: SameOrigin já garantido pelo Next.js 16.
- Route Handlers que recebem do próprio frontend: sem CORS aberto. Webhook público (WhatsApp, Stripe): validar assinatura.
- Security headers em `next.config.js`:
  ```ts
  headers: [
    { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains; preload" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: "geolocation=(), camera=(), microphone=()" },
  ]
  ```
- CSP: `default-src 'self'; img-src 'self' data: <supabase-storage-host>; script-src 'self';` — ajustar com cautela.

## 8. Rate limit e captcha

- **Endpoint público de agendamento** (`/api/appointments` vindo de `[slug]`): rate limit por IP (ex: 10 req/min) + hCaptcha no formulário.
- **Login/register:** limitar tentativas por email + IP para evitar brute force (Supabase Auth já tem, reforçar com middleware se necessário).
- Logs de tentativas suspeitas → tabela `security_events` com TTL.

## 9. Pagamentos

- NUNCA armazenar PAN, CVV, validade no banco. Stripe/Pagar.me tokeniza.
- Webhooks de pagamento: validar assinatura (`stripe.webhooks.constructEvent`).
- Split payment: configurar no gateway, NUNCA fazer "manualmente" movendo dinheiro.
- Reembolso → sempre via gateway + `audit_logs`.

## 10. Dados pessoais e LGPD

- Minimizar coleta: só o necessário para agendar (nome, telefone, opcional email).
- Cliente final tem direito de solicitar exclusão → implementar `DELETE /api/clients/:id` que anonimiza (`name='—'`, `phone=null`, `email=null`) mantendo histórico de agendamentos para o tenant (integridade referencial).
- Exportação de dados por solicitação: rota administrativa que gera JSON do client requisitante (autenticado + confirmação).
- Política de privacidade e termos de uso publicados em `/politica-privacidade` e `/termos`.

## 11. Storage (Supabase)

- Buckets por categoria: `logos`, `avatars`, `services`.
- Policies de Storage por `tenant_id`:
  ```sql
  CREATE POLICY "tenant_upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'avatars'
      AND (storage.foldername(name))[1] = (
        SELECT tenant_id::text FROM users WHERE id = auth.uid()
      )
    );
  ```
- URL pública só para arquivos marcados como públicos (logo do salão). Documentos privados → signed URL com TTL.

## 12. Auditoria

Tabela `audit_logs`:
```sql
CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  actor_id uuid REFERENCES users(id),
  action text NOT NULL,          -- ex: 'appointment.cancel'
  target_type text NOT NULL,
  target_id uuid,
  payload jsonb,                 -- NUNCA dados crus sensíveis; preferir hash/resumo
  created_at timestamptz DEFAULT now()
);
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "audit_read_owner_manager" ON audit_logs
  FOR SELECT USING (
    tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid())
    AND (SELECT role FROM users WHERE id = auth.uid()) IN ('owner','manager')
  );
```

Toda ação sensível (cancelar, alterar preço, mudar comissão, excluir cliente) grava em `audit_logs`.

## 13. Dependências

- SEMPRE `npm audit --omit=dev` antes de build de produção.
- NUNCA instalar pacote com <1k downloads/semana ou sem commits nos últimos 6 meses sem justificativa.
- `.npmrc`: `engine-strict=true`.

## 14. Checklist rápido antes de PR

- [ ] Nenhum segredo/key em diff
- [ ] RLS ativa em todas as tabelas tocadas
- [ ] Policies cobrem os 4 verbos
- [ ] Zod valida toda entrada externa
- [ ] `service_role` só em `lib/supabase/admin.ts`
- [ ] Middleware protegendo `/admin/*`
- [ ] Rate limit em endpoints públicos de mutação
- [ ] `audit_logs` gravando ações sensíveis
- [ ] Logs não expõem PII
