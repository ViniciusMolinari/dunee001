#!/usr/bin/env bash
# =============================================================================
# validate-rules.sh — Validação automática das regras do CLAUDE.md (Dunee 001)
# -----------------------------------------------------------------------------
# Roda no pre-commit (via .githooks/pre-commit) e verifica apenas arquivos
# staged. Divide-se em três grupos de checagem:
#   1. Código TS/TSX: limites de linhas, anti-patterns, segurança, multi-tenant.
#   2. Migrations SQL: RLS obrigatória, tenant_id em tabelas novas.
#   3. Universais:   .env commitado, diff em arquivos de regra.
# Referência: CLAUDE.md + .claude/rules/*.md
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# CORES
# ----------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

# ----------------------------------------------------------------------------
# HELPERS
# ----------------------------------------------------------------------------
err() {
  # err <file[:line]> <titulo> <dica>
  echo -e "  ${RED}✗ $2${NC} — $1"
  [ -n "${3:-}" ] && echo -e "    ${YELLOW}→ $3${NC}"
  ERRORS=$((ERRORS+1))
}

warn() {
  echo -e "  ${YELLOW}⚠ $2${NC} — $1"
  [ -n "${3:-}" ] && echo -e "    ${YELLOW}→ $3${NC}"
  WARNINGS=$((WARNINGS+1))
}

first_line() {
  # first_line <file> <regex>
  grep -nE "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1 || true
}

has_server_only() {
  # arquivos server-only declarados (import "server-only" ou caminho em lib/supabase/admin)
  local file="$1"
  grep -qE '^\s*import\s+["\x27]server-only["\x27]' "$file" 2>/dev/null && return 0
  [[ "$file" == *"lib/supabase/admin"* ]] && return 0
  [[ "$file" == *"/api/"* ]] && return 0
  [[ "$file" == *"route.ts" ]] && return 0
  return 1
}

is_client_file() {
  head -5 "$1" 2>/dev/null | grep -qE '^\s*["\x27]use client["\x27]'
}

# ============================================================================
# COLETA DE ARQUIVOS STAGED
# ============================================================================
STAGED_TS=$(git diff --cached --name-only --diff-filter=AM | grep -E '\.(ts|tsx)$' || true)
STAGED_SQL=$(git diff --cached --name-only --diff-filter=AM | grep -E '^supabase/migrations/.*\.sql$' || true)
STAGED_ALL=$(git diff --cached --name-only --diff-filter=AM || true)

# Nada para validar? sai em verde.
if [ -z "$STAGED_TS" ] && [ -z "$STAGED_SQL" ] && [ -z "$STAGED_ALL" ]; then
  exit 0
fi

echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  Dunee 001 — Validação de Regras (CLAUDE.md)${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# 0. UNIVERSAIS (qualquer arquivo)
# ============================================================================
check_universal() {
  local file="$1"

  # .env* nunca commitado (exceto .env.example)
  if [[ "$file" == .env* && "$file" != ".env.example" && "$file" != ".env.sample" ]]; then
    err "$file" ".env commitado" "Adicionar ao .gitignore; usar .env.example como template"
  fi

  # URL provisória Vercel em código/config (NUNCA hardcodar subdomínio .vercel.app)
  if [[ "$file" == *.ts || "$file" == *.tsx || "$file" == *.json || "$file" == *.md ]]; then
    if grep -qnE '[a-z0-9-]+\.vercel\.app' "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" '[a-z0-9-]+\.vercel\.app')
      err "$file:$ln" "URL .vercel.app hardcoded" "Usar dunee.com.br ou variável de ambiente"
    fi
  fi

  # Referências a Firebase (stack é Supabase/Vercel)
  if [[ "$file" == *.ts || "$file" == *.tsx ]]; then
    if grep -qnE '(firebase/|firebase-admin|firestore|onSnapshot\()' "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" 'firebase/|firebase-admin|firestore|onSnapshot\(')
      err "$file:$ln" "Referência a Firebase" "Stack é Supabase — ver .claude/rules/multi-tenant.md"
    fi
  fi
}

# ============================================================================
# 1. LIMITES DE LINHAS
# ============================================================================
check_line_limits() {
  local file="$1"
  local lines; lines=$(wc -l < "$file")
  local limit=300; local type="Arquivo"

  case "$file" in
    src/app/api/*|src/app/*/api/*|*/route.ts)
      limit=150; type="Route Handler";;
    src/components/*|*/_components/*|*/components/*)
      limit=200; type="Componente";;
    src/hooks/*|src/lib/*)
      limit=250; type="Hook/Lib";;
    src/app/*/page.tsx|src/app/*/*/page.tsx|src/app/*/*/*/page.tsx)
      limit=300; type="page.tsx";;
  esac

  if [ "$lines" -gt "$limit" ]; then
    err "$file" "LIMITE DE LINHAS (${type}: ${lines}/${limit})" \
      "Extrair sub-componente, hook ou util"
  fi
}

# ============================================================================
# 2. ANTI-PATTERNS DE CÓDIGO (TS/TSX)
# ============================================================================
check_anti_patterns() {
  local file="$1"

  # ---- TypeScript: any / @ts-ignore ----
  if grep -qnE '(:\s*any\b|<any>|as\s+any\b)' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" '(:\s*any\b|<any>|as\s+any\b)')
    err "$file:$ln" "TIPO any PROIBIDO" "Usar unknown + narrowing, ou type de @/types/database"
  fi
  if grep -qnE '@ts-ignore' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" '@ts-ignore')
    err "$file:$ln" "@ts-ignore PROIBIDO" "Usar @ts-expect-error com justificativa + data"
  fi
  if grep -qnE '@ts-expect-error\s*$' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" '@ts-expect-error\s*$')
    warn "$file:$ln" "@ts-expect-error SEM COMENTÁRIO" "Incluir motivo + data na mesma linha"
  fi

  # ---- Imagem: <img> em vez de next/image ----
  if [[ "$file" == *.tsx ]]; then
    if grep -qnE '<img[[:space:]]' "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" '<img[[:space:]]')
      err "$file:$ln" "<img> PROIBIDO" "Usar next/image (perf + LCP)"
    fi
  fi

  # ---- console.error/warn server-side ----
  if grep -qnE 'console\.(error|warn|log)\(' "$file" 2>/dev/null; then
    if ! is_client_file "$file"; then
      local ln; ln=$(first_line "$file" 'console\.(error|warn|log)\(')
      warn "$file:$ln" "console.* em server-side" \
        "Usar logger estruturado (sem PII em texto claro)"
    fi
  fi

  # ---- Math.random() para IDs ----
  if grep -qnE 'Math\.random\(\)' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" 'Math\.random\(\)')
    err "$file:$ln" "Math.random() PROIBIDO" "Usar crypto.randomUUID() ou nanoid"
  fi

  # ---- Formatação manual de moeda ----
  if grep -qnE '\.toFixed\([0-9]+\)\.replace' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" '\.toFixed\([0-9]+\)\.replace')
    err "$file:$ln" "FORMATAÇÃO MANUAL DE MOEDA" \
      "Usar Intl.NumberFormat('pt-BR', { style:'currency', currency:'BRL' })"
  fi

  # ---- Cálculo manual de data ----
  if grep -qnE 'getTime\(\)\s*[\+\-]\s*[0-9]' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" 'getTime\(\)\s*[\+\-]\s*[0-9]')
    err "$file:$ln" "CÁLCULO MANUAL DE DATA" "Usar date-fns (addDays, differenceInMinutes…)"
  fi

  # ---- catch vazio ----
  if grep -qnE 'catch\s*\([^)]*\)\s*\{\s*\}' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" 'catch\s*\([^)]*\)\s*\{\s*\}')
    err "$file:$ln" "CATCH VAZIO" "Logar (sem PII) ou propagar"
  fi

  # ---- Segredo hardcoded ----
  if grep -qnEi '(api_?key|secret|service_role|password|token)\s*[:=]\s*["\x27][A-Za-z0-9_\-]{12,}["\x27]' "$file" 2>/dev/null; then
    if ! grep -qE 'process\.env' "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" '(api_?key|secret|service_role|password|token)\s*[:=]\s*["\x27]')
      err "$file:$ln" "POSSÍVEL SEGREDO HARDCODED" "Usar process.env.* (ver .claude/rules/seguranca.md)"
    fi
  fi

  # ---- Fallback de secret ----
  if grep -qnE "\|\|\s*['\"](fallback|changeme|dev|test|secret)" "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" "\|\|\s*['\"](fallback|changeme|dev|test|secret)")
    err "$file:$ln" "FALLBACK DE SECRET" "Throw quando env ausente — nunca silenciar"
  fi

  # ---- Hex color hardcoded em JSX ----
  if [[ "$file" == *.tsx ]]; then
    if grep -qnE "['\"]#[0-9a-fA-F]{3,8}['\"]" "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" "['\"]#[0-9a-fA-F]{3,8}['\"]")
      warn "$file:$ln" "HEX COLOR HARDCODED" \
        "Usar token do tailwind.config / CSS var (identidade Dunee)"
    fi
  fi

  # =========================================================================
  # MULTI-TENANT & SUPABASE
  # =========================================================================

  # ---- service_role fora de server-only ----
  if grep -qnE 'SUPABASE_SERVICE_ROLE_KEY' "$file" 2>/dev/null; then
    if ! has_server_only "$file"; then
      local ln; ln=$(first_line "$file" 'SUPABASE_SERVICE_ROLE_KEY')
      err "$file:$ln" "SERVICE_ROLE FORA DE SERVER-ONLY" \
        "Só permitido em lib/supabase/admin.ts ou arquivos com import \"server-only\""
    fi
  fi

  # ---- NEXT_PUBLIC_ + palavras sensíveis ----
  if grep -qnE 'NEXT_PUBLIC_[A-Z_]*(SECRET|SERVICE_ROLE|PRIVATE|TOKEN|PASSWORD)' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" 'NEXT_PUBLIC_[A-Z_]*(SECRET|SERVICE_ROLE|PRIVATE|TOKEN|PASSWORD)')
    err "$file:$ln" "SEGREDO COM PREFIXO NEXT_PUBLIC_" \
      "NEXT_PUBLIC_ vai no bundle do browser — remover prefixo"
  fi

  # ---- Código específico de um tenant ----
  if grep -qnE 'tenant(\.|_)(id|slug|name)\s*===?\s*["\x27][A-Za-z0-9_\-]+["\x27]' "$file" 2>/dev/null; then
    local ln; ln=$(first_line "$file" 'tenant(\.|_)(id|slug|name)\s*===?\s*["\x27]')
    err "$file:$ln" "CÓDIGO ESPECÍFICO DE TENANT" \
      "Features são multi-tenant por construção — ver .claude/rules/multi-tenant.md"
  fi

  # ---- Query Supabase sem filtro por tenant_id ----
  # Heurística: .from('tabela').select/insert/update/delete sem .eq('tenant_id', ...) no mesmo bloco
  if grep -qnE "\.from\(['\"][a-z_]+['\"]\)" "$file" 2>/dev/null; then
    # ignorar arquivos de tipos e tabelas globais conhecidas
    if ! grep -qE "\.eq\(['\"]tenant_id['\"]" "$file" 2>/dev/null \
       && ! grep -qE "\.from\(['\"](tenants|countries|pg_|auth\.)" "$file" 2>/dev/null; then
      local ln; ln=$(first_line "$file" "\.from\(['\"][a-z_]+['\"]\)")
      warn "$file:$ln" "QUERY SUPABASE SEM .eq('tenant_id', …)" \
        "Filtrar explicitamente por tenant_id (performance + intenção clara)"
    fi
  fi

  # ---- Realtime channel direto (sugerir hook) ----
  if grep -qnE "\.channel\(['\"]" "$file" 2>/dev/null; then
    if [[ "$file" != *"/hooks/"* && "$file" != *"/lib/realtime"* ]]; then
      local ln; ln=$(first_line "$file" "\.channel\(['\"]")
      warn "$file:$ln" "SUPABASE REALTIME DIRETO" \
        "Encapsular em hook (useRealtimeAppointments, etc.)"
    fi
  fi

  # ---- Validação de entrada sem Zod em Route Handler / Server Action ----
  if [[ "$file" == *"route.ts" || "$file" == *"actions.ts" || "$file" == *"/actions/"* ]]; then
    if grep -qE 'await\s+req\.json\(\)' "$file" 2>/dev/null || grep -qE '"use server"' "$file" 2>/dev/null; then
      if ! grep -qE '(\bz\.|from\s+["\x27]zod["\x27]|\.parse\(|\.safeParse\()' "$file" 2>/dev/null; then
        warn "$file" "ENTRADA EXTERNA SEM ZOD" \
          "Validar req.json() / inputs com Zod (ver .claude/rules/seguranca.md)"
      fi
    fi
  fi
}

# ============================================================================
# 3. MIGRATIONS SUPABASE
# ============================================================================
check_migration() {
  local file="$1"
  # Lowercased copy do conteúdo para matching case-insensitive portável (BSD awk não tem IGNORECASE)
  local lc; lc=$(tr 'A-Z' 'a-z' < "$file")

  # CREATE TABLE sem tenant_id (exceto tabela tenants e lookups globais conhecidos)
  if printf '%s\n' "$lc" | grep -qE 'create[[:space:]]+table' 2>/dev/null; then
    # Extrai nomes de tabelas criadas (em minúsculo)
    local tables
    tables=$(printf '%s\n' "$lc" \
             | grep -oE 'create[[:space:]]+table[[:space:]]+(if[[:space:]]+not[[:space:]]+exists[[:space:]]+)?[a-z0-9_.]+' \
             | awk '{print $NF}' | tr -d '"' || true)
    for tbl in $tables; do
      case "$tbl" in
        tenants|countries|audit_logs|migrations|schema_migrations)
          continue;;
      esac
      # Verifica se o bloco CREATE TABLE <tbl> (...); contém tenant_id
      if ! printf '%s\n' "$lc" | awk -v t="$tbl" '
        $0 ~ "create[[:space:]]+table[[:space:]]+(if[[:space:]]+not[[:space:]]+exists[[:space:]]+)?"t"([[:space:]]|[(])" {inside=1}
        inside && /tenant_id/ {found=1}
        inside && /;/ {inside=0}
        END{exit !found}
      '; then
        err "$file" "TABELA '$tbl' SEM tenant_id" \
          "Adicionar: tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE"
      fi
    done

    # RLS obrigatória: deve haver ENABLE ROW LEVEL SECURITY para cada tabela criada
    for tbl in $tables; do
      case "$tbl" in
        tenants|countries|migrations|schema_migrations)
          continue;;
      esac
      if ! printf '%s\n' "$lc" | grep -qE "alter[[:space:]]+table[[:space:]]+$tbl[[:space:]]+enable[[:space:]]+row[[:space:]]+level[[:space:]]+security"; then
        err "$file" "RLS NÃO ATIVADA em '$tbl'" \
          "Adicionar: ALTER TABLE $tbl ENABLE ROW LEVEL SECURITY;"
      fi
      if ! printf '%s\n' "$lc" | grep -qE "create[[:space:]]+policy.*on[[:space:]]+$tbl"; then
        err "$file" "SEM POLICY para '$tbl'" \
          "Criar policies SELECT/INSERT/UPDATE/DELETE por tenant_id"
      fi
    done
  fi

  # DROP TABLE — exige confirmação manual
  if printf '%s\n' "$lc" | grep -qE '(^|[^a-z_])drop[[:space:]]+table' 2>/dev/null; then
    warn "$file" "DROP TABLE detectado" "Confirmar com backup + plano de rollback"
  fi

  # TRUNCATE — perigo
  if printf '%s\n' "$lc" | grep -qE '(^|[^a-z_])truncate[[:space:]]' 2>/dev/null; then
    err "$file" "TRUNCATE em migration" "Nunca truncar dados em produção por migration"
  fi
}

# ============================================================================
# EXECUTAR
# ============================================================================
if [ -n "$STAGED_ALL" ]; then
  for file in $STAGED_ALL; do
    [ -f "$file" ] || continue
    check_universal "$file"
  done
fi

if [ -n "$STAGED_TS" ]; then
  COUNT_TS=$(echo "$STAGED_TS" | grep -c . || true)
  echo -e "${BOLD}• ${CYAN}${COUNT_TS}${NC}${BOLD} arquivo(s) .ts/.tsx${NC}"
  for file in $STAGED_TS; do
    [ -f "$file" ] || continue
    check_line_limits "$file"
    check_anti_patterns "$file"
  done
fi

if [ -n "$STAGED_SQL" ]; then
  COUNT_SQL=$(echo "$STAGED_SQL" | grep -c . || true)
  echo -e "${BOLD}• ${CYAN}${COUNT_SQL}${NC}${BOLD} migration(s) SQL${NC}"
  for file in $STAGED_SQL; do
    [ -f "$file" ] || continue
    check_migration "$file"
  done
fi

# ============================================================================
# RESULTADO
# ============================================================================
echo ""
echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────${NC}"

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}${BOLD}  ✗ ${ERRORS} erro(s) — commit BLOQUEADO${NC}"
  [ "$WARNINGS" -gt 0 ] && echo -e "${YELLOW}  ⚠ ${WARNINGS} aviso(s)${NC}"
  echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${BOLD}Corrija os erros acima antes de commitar.${NC}"
  echo -e "  Referência: ${CYAN}CLAUDE.md${NC} e ${CYAN}.claude/rules/${NC}"
  echo -e "  Para pular em emergência: ${YELLOW}git commit --no-verify${NC} (desencorajado)"
  echo ""
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}  ⚠ ${WARNINGS} aviso(s) — commit permitido${NC}"
  echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────${NC}"
  echo ""
  exit 0
else
  echo -e "${GREEN}${BOLD}  ✓ Todas as regras validadas — commit OK${NC}"
  echo -e "${CYAN}${BOLD}──────────────────────────────────────────────────${NC}"
  echo ""
  exit 0
fi
