# Meta-Regras — Como manter e estender o sistema de regras

> Este arquivo define COMO o Claude deve trabalhar neste repositório e COMO manter o próprio sistema `CLAUDE.md + .claude/rules/*`.

## 1. Filosofia em duas camadas

- **CLAUDE.md (raiz):** índice de decisão rápida. Cada regra em 1–2 linhas. Formato **SEMPRE/NUNCA**. Limite sugerido: ~35k caracteres.
- **`.claude/rules/*.md`:** detalhamento por domínio, com exemplos de código, tabelas, comandos, checklists. Sem limite de tamanho — o foco é ser útil como referência.

Regra-mestra: se uma regra do `CLAUDE.md` precisa de mais contexto, ela mora resumida lá e expandida em `.claude/rules/<dominio>.md`. NUNCA duplicar conteúdo — linkar.

## 2. Fluxo obrigatório antes de codar

1. **Ler o pedido** e identificar o domínio (agenda, auth, página pública, financeiro, multi-tenant, infra).
2. **Explorar** os arquivos relacionados (`src/`, `supabase/migrations/`, `CLAUDE.md`, arquivo de regra do domínio).
3. **Apresentar plano** em PT-BR:
   - O que será feito, em etapas
   - Arquivos criados / alterados
   - Impacto em multi-tenant e segurança (RLS, policies, roles)
   - Riscos / trade-offs
   - Alternativas (quando houver >1 abordagem razoável)
4. **Aguardar aprovação explícita** ("pode", "prossiga", "ok", "manda ver") antes de escrever código.
5. **Implementar em blocos revisáveis** — não despejar tudo de uma vez.
6. **Rodar checklist** do domínio (`.claude/rules/checklist.md`).
7. **Reportar** em PT-BR: o que mudou, como testar, pendências.

## 3. Quando atualizar as regras

Atualize o `CLAUDE.md` e/ou `.claude/rules/*.md` SEMPRE que:

- Uma decisão arquitetural mudar (ex: troca de Resend por outra provedora de email).
- Um novo módulo entrar (ex: estoque, fidelidade) — precisa aparecer em `modulos.md` e checklist.
- Uma dor recorrente surgir (ex: "toda vez esquece do índice composto") — vira NUNCA no anti-pattern.
- Uma biblioteca/ferramenta for adicionada ao stack (ex: Zod, React Query) — aparece em `codigo.md`.
- A estrutura de pastas mudar — atualizar o bloco em `CLAUDE.md` seção "Estrutura de Pastas".

Regras precisam envelhecer bem: se uma regra ficou obsoleta (ex: após V2 entrar, não é mais "futuro"), reescreva — não deixe rastro confuso.

## 4. Como escrever uma regra nova

- Comece por **SEMPRE** ou **NUNCA**. Sem "talvez", "considere", "tente".
- Uma frase. Máx duas. Se precisar de parágrafo, o detalhe vai em `.claude/rules/`.
- Se for específica de domínio, coloque no arquivo do domínio e adicione um bullet resumido em `CLAUDE.md`.
- Se a regra tem exceção, documente a exceção no mesmo bullet ("…exceto quando X").
- Exemplos concretos (trechos de código) SÓ em `.claude/rules/*`. `CLAUDE.md` é índice.

## 5. Como apresentar opções ao usuário

Quando houver trade-off real, entregue no formato:

```
Opção A — <nome curto>
- Prós: …
- Contras: …
- Esforço: baixo/médio/alto

Opção B — <nome curto>
- Prós: …
- Contras: …

Recomendação: A / B / depende de X. Quer que eu siga por onde?
```

NUNCA decidir sozinho em bifurcação importante (ex: Server Action vs API Route, Zustand vs Context, Realtime vs Polling).

## 6. Comunicação com o usuário

- SEMPRE PT-BR. Mesmo em log, commit, comentário, tooltip de UI.
- Objetividade > cordialidade. Evite "com certeza!", "ótima pergunta". Vá direto.
- Ao reportar entrega, use: **Feito / Mudanças / Como testar / Pendências**.
- Se detectar ambiguidade no pedido, pergunte antes de codar. Uma pergunta específica economiza mais que três iterações erradas.

## 7. Limites de escopo

- NUNCA expandir escopo sem autorização. Se notar tech debt adjacente, apontar no reporte como pendência — não consertar no mesmo PR.
- NUNCA criar documentação paralela (README, docs/, wikis) sem pedido explícito.
- NUNCA adicionar dependência sem alinhar. Cada nova dep = mais superfície de manutenção/segurança.

## 8. Integração com memória do Claude Code

- O hook `SessionStart` já cuida de `gh auth switch` para a conta correta do projeto. Confirmar com `gh auth status` se houver dúvida.
- Memória de conversas anteriores pode estar desatualizada em relação ao código — em conflito, código atual manda.
