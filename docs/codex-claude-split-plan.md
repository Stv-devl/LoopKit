# Partage de travail Claude / Codex dans `/loop:orchestrate`

> Statut : brouillon à relire, pas encore implémenté. Ceci n'est pas un
> artefact de `/loop:orchestrate` (pas de `docs/work/<slug>/` ni d'entrée
> officielle dans le board) — c'est une note de travail sur l'outillage du kit
> lui-même, à faire passer par la loop (ou en édition directe des commandes)
> le jour où on l'implémente.

**Point d'entrée pour la prochaine session — le plan en entier, dans cet
ordre, un commit par volet.**

Un seul volet dépend réellement du POC (`.codex/config.toml` et
§"Garde-fous non-TDD" — construire ça sur une hypothèse non testée serait
bâtir sur du sable). Les quatre autres n'en dépendent pas et peuvent suivre
dans la même session, mais **chacun se vérifie et se committe séparément**
avant d'attaquer le suivant — on vient de trouver 3 incohérences réelles rien
qu'en relisant ce *document* une fois ; les isoler par volet est ce qui rend
une erreur facile à retrouver plutôt que noyée dans un seul gros commit.

0. **Pré-check bloquant** : `command -v codex`. Absent → s'arrêter, rien de
   ce plan n'est testable tant que Codex CLI n'est pas installé sur cette
   machine ; ne pas improviser un test partiel. (Déjà vérifié sur cette
   machine au moment d'écrire ce plan : présent, `codex-cli 0.147.0`.)

1. **POC hooks** (§"POC hooks") — **fait, 2026-09-07, ÉCHEC.** Détail complet,
   preuves et conséquences dans §"POC hooks" étape 5. En bref : le tool call
   réel n'est pas `apply_patch` mais `exec` (wrapping JS `tools.apply_patch`,
   feature `CodeModeHost`), et les hooks `PreToolUse` projet n'ont jamais été
   invoqués faute de confiance persistée accordable hors d'une session TUI
   interactive (`--dangerously-bypass-hook-trust` requis, refusé par le
   classifieur de sécurité de la session qui a exécuté le test). Ligne
   "EXECUTE — RED en plus" du tableau coût/bénéfice (§"Où pousser plus loin")
   mise à jour : `Ne pas faire`, confirmé et refermé.

2. ~~**Si le POC passe** : `.codex/config.toml` + §"Garde-fous non-TDD"~~ —
   **volet sauté entièrement** (POC en échec, cf. 1. — "ne pas committer une
   config qui repose sur un mécanisme non confirmé"). Aucun fichier créé ;
   `no-any-type`/`enforce-architecture`/`no-forbidden-icons`/
   `english-comments` restent Claude-only, sans équivalent Codex pour
   l'instant. Le filet `reviewer.md` (point 2 de §"Garde-fous non-TDD",
   critère icônes interdites) ne dépendait pas du POC — traité au volet 3
   ci-dessous avec le reste des fichiers indépendants.

3. **Routeur déclaratif + frontmatter** (`.claude/workflow-routing.yml`,
   `orchestrate.md`, `handoff/codex.md`, `AGENTS.md`) — indépendant du POC.
   Vérification : les bullets correspondants de §"Vérification" (fichier
   absent → comportement inchangé ; Codex absent du `PATH` → même repli ;
   3 branches de reprise sur un handoff réel). Commit séparé.
   **Fait, 2026-09-07.** Les quatre fichiers sont à jour ; vérification par
   lecture croisée faite (fichier absent → chemins inchangés dans
   `orchestrate.md`, la même commande `command -v codex` que
   `codex-handoff.sh:7` est citée aux deux points de bascule). La vérification
   "3 branches sur un handoff réel" reste à faire sur un vrai handoff produit
   par une feature — aucun `docs/work/` n'existe encore dans ce repo pour la
   tester en conditions réelles ; notée comme dette dans §"Vérification".

4. **Sonde kit-health** — indépendant du POC. Vérification :
   `kit-doctor.py` rapporte une entrée `health` non vide après quelques
   événements réels (gate, refus de hook). Commit séparé.
   **Fait, 2026-09-07.** `.claude/.kit-health.jsonl` (gitignoré), résumé dans
   `check_kit_health()` (nouvelle catégorie `health` de `kit-doctor.py`,
   statut `OK`/`skip` uniquement — jamais `DIVERGENCE`, ce n'est pas un jumeau,
   cf. la nuance posée plus haut). Émetteurs branchés : `kit-attempts.py`
   (`record()`/`clear()`), les six hooks de refus
   (`tdd-require-red.sh`, `no-any-type.sh`, `no-forbidden-icons.sh`,
   `enforce-architecture.py`, `english-comments.py`,
   `prevent-destructive-commands.sh` — seulement sur une vraie décision `deny`,
   pas `ask`), et `/loop:review` (une ligne par finding + verdict, étape 1bis
   de SYNTHESIS, écrite par le fil principal puisque `reviewer`/`verifier` sont
   read-only). Vérifié par des payloads réels sur `no-any-type.sh` (bash) et
   `enforce-architecture.py` (python) — les deux ajoutent bien leur ligne au
   refus réel. `python3 .claude/hooks/kit-doctor.py` reste `No divergence`
   avec le fichier absent (`skip`) et rapporte un résumé correct testé avec un
   fichier synthétique (gate le plus en échec, hook qui refuse le plus,
   confirmé/réfuté par dimension REVIEW, lignes malformées comptées à part).
   Aucune feature réelle n'a encore tourné dans ce repo pour peupler le
   fichier en conditions réelles — cf. §"Vérification".

5. **Réattribution des tiers Claude** — indépendant du POC. Vérification :
   `python3 .claude/hooks/kit-doctor.py` → `agent-models: OK`, décompte 5
   `inherit` / 6 `sonnet` / 1 `haiku`. Commit séparé.
   **Fait, 2026-09-07.** Table de `11-token-budget.md` remplacée (37 lignes,
   budget 55, rien à compenser) ; `model: inherit → sonnet` sur
   `test-writer.md`/`e2e-tester.md`/`github.md`/`designer.md`,
   `model: haiku → sonnet` sur `story-writer.md`. `kit-doctor.py` confirme
   `agent-models 12 agents — haiku=1, inherit=5, sonnet=6` et `No divergence`
   globalement. Les deux mesures "Après" du plan (allers-retours RED de
   `test-writer`, findings `story-critic` sur les stories de `story-writer`)
   restent à observer sur une feature réelle — aucune n'a encore tourné dans
   ce repo, cf. §"Vérification".

6. **Économie côté Codex** (effort par rôle dans le routeur + la table de
   relais dans `AGENTS.md`) — dépend du volet 3 (le routeur doit exister).
   Vérification : `codex-handoff.sh` ajoute bien le flag d'effort attendu sur
   un rôle `codex_effort: low`, rien sur fichier absent. Commit séparé.
   **Fait, 2026-09-07.** `codex-handoff.sh` prend un second argument optionnel
   (le rôle : `execute-green`, `review-fixes`…), lit sa ligne dans
   `.claude/workflow-routing.yml` par `grep`/`sed` (pas de parseur YAML pour un
   fichier à une ligne par rôle) et ajoute `-c model_reasoning_effort=<niveau>`
   seulement si `provider: codex` et `codex_effort` sont présents sur cette
   ligne. `orchestrate.md` passe désormais ce rôle aux deux commandes
   imprimées (`execute-green`, `review-fixes`) ; `/handoff:codex` (bascule
   manuelle, aucun rôle précis) continue d'imprimer la commande sans rôle,
   comportement inchangé. `AGENTS.md` porte la table rôle→effort du relais
   complet. Vérifié par exécution réelle du script (un `exec codex` remplacé
   par un `echo` le temps du test, jamais commité) sur les trois cas : rôle
   `execute-green` → `-c model_reasoning_effort=low` présent ; aucun rôle →
   commande identique à avant ce volet ; `.claude/workflow-routing.yml`
   temporairement absent avec un rôle passé quand même → aucun flag ajouté,
   pas d'erreur.

`docs/RATIONALE.md` et `docs/Claude_Workflows.md` se mettent à jour une fois
que les volets qu'ils décrivent sont committés, pas avant — une doc
narrative qui décrit un mécanisme pas encore committé serait fausse dès son
propre commit.

## Context

Deux abonnements coexistent (Claude ~90€, Codex ~20€). Le kit a déjà un relais
automatique Claude → Codex en cas de saturation (`workflow.py` +
`.claude/.codex-ready`, cf. `.claude/guides/11-token-budget.md`) et un relais
manuel (`/handoff:codex` + `codex-handoff.sh`), mais les deux sont pensés comme
un **filet de secours**, jamais comme un partage voulu du travail. L'objectif
ici : rendre la répartition **délibérée** (Codex fait l'implémentation
mécanique, Claude garde le jugement) et couvrir les deux sens de repli — Codex
indisponible/à sa limite → tout sur Claude ; Claude à sa limite → tout sur
Codex (déjà le cas).

Recherche préalable faite en amont de ce brouillon : lecture de
`.claude/commands/loop/orchestrate.md`, `.claude/commands/handoff/codex.md`,
`codex-handoff.sh`, `workflow.py`, `AGENTS.md`, `docs/RATIONALE.md`,
`docs/Claude_Workflows.md`. Point important trouvé et **volontairement laissé
de côté** sur demande explicite : `docs/audits/workflow.md` contient déjà 3
findings confirmés et ouverts sur ce mécanisme (W-01 : la regex de détection
de limite matche le code source de `workflow.py` lui-même, donc un `cat`/`git
diff` du fichier coupe la session pour rien ; W-05 : trois docs promettent un
relais automatique à 95% de quota que le code ne fait pas — seul un message
explicite de limite déclenche le relais ; W-11 : la doc dit que le
superviseur "attend la frontière atomique suivante", le code interrompt
immédiatement puis SIGTERM après 8s). Ces trois bugs restent tels quels,
déjà tracés dans ce registre — pas de correctif dans ce plan.

## Qui fait quoi dans le workflow

Deux répartitions orthogonales : **quel outil pilote** (Claude Code ou Codex,
ci-dessous) et **quel tier de modèle** chaque sous-agent Claude utilise
(section suivante — les sous-agents `.claude/agents/*.md` ne sont invocables
que depuis une session Claude, jamais depuis Codex).

| Phase du loop | Agents lancés (tier cible) | Pilote |
| --- | --- | --- |
| RESEARCH | `explorer` (haiku), `doc-researcher` (sonnet) | Claude |
| INTERFACE | `designer` (sonnet) ; juge sur le main thread en economy/standard, un `designer` sonnet supplémentaire en mode juge si critical | Claude |
| PLAN | `plan-critic` (inherit), `verifier` (inherit) | Claude |
| EXECUTE — RED (utils/mapper/repository) | `test-writer` (sonnet) | Claude — les hooks TDD (`tdd-prove-red`, `tdd-require-red`, `tdd-freeze-tests`) n'existent que côté Claude Code |
| EXECUTE — GREEN / wiring / DB / backend / test-après | aucun sous-agent, implémentation directe | **Codex** si disponible sur le PATH, sinon Claude inline (comportement actuel inchangé) |
| REVIEW — jugement (findings + verdict) | `reviewer` (inherit), `verifier` (inherit), `e2e-tester` (sonnet) | Claude |
| REVIEW — correction des findings Critical/Major | aucun sous-agent, implémentation directe | **Codex** si disponible, sinon Claude inline (comportement actuel inchangé) |
| SHIP | `github` (sonnet), `security-auditor` (inherit, si profil critical) | Claude |
| BMAD — SM (hors loop) | `story-writer` (sonnet) | Claude |
| stories:review (hors loop) | `story-critic` (inherit) | Claude |

**Nuance importante trouvée en croisant les deux plans** : la bascule
délibérée vers Codex (section suivante) ne peut porter que sur la partie
**GREEN / non test-first** d'EXECUTE. Le cycle RED (`test-writer`, un
sous-agent Claude, plus les trois hooks TDD qui interceptent `Write`/`Edit`
côté Claude Code) n'a pas d'équivalent connu côté Codex — `AGENTS.md` ne fait
que *demander* à Codex de respecter `05-testing.md`, rien ne l'impose comme
le fait le hook. Donc l'ordre pratique reste : Claude termine les cycles
RED→GREEN des couches test-first (ou au moins pose les RED), *puis* la
bascule vers Codex ne couvre que ce qui reste (DB, backend, wiring,
`hooks.ts`, composants, tests après-coup) — pas un simple "tout EXECUTE part
sur Codex à la fin de PLAN". À affiner au moment de l'implémentation.

**Ce raisonnement ne couvre que la bascule délibérée — Claude choisit le
moment, donc peut choisir de finir RED d'abord.** Le relais complet
(§"Repli dans les deux sens" point 2) n'a pas ce luxe : `workflow.py`
déclenche le relais sur un signal externe (quota), pas sur une frontière
propre. `11-token-budget.md` demande bien à Claude de "finish the current
atomic write/test" avant de céder la main — mais W-11 (§Context, laissé tel
quel dans ce plan) dit exactement que ça ne marche pas comme documenté : le
superviseur interrompt et SIGTERM après 8s, sans garantie d'avoir attendu la
frontière. Donc une couche test-first peut arriver **mi-RED, sans marqueur**,
pile au moment où Codex doit prendre seul le relais — et c'est là qu'"aucun
repli Codex connu" (table plus bas) devient concret : Codex ne doit pas
continuer cette couche en test-après silencieux (ce serait exactement la
violation que `tdd-require-red` existe pour empêcher), il doit **s'arrêter
sur cette couche précise et le signaler dans le checkpoint**, en continuant
sur tout le reste (DB, wiring, composants…) qui n'est pas concerné. Ce trou
se referme de lui-même si le POC hooks (§"POC hooks") et le portage des
garde-fous non-TDD (§"Garde-fous non-TDD") aboutissent — pas avant.

## Ce que Codex CLI sait reproduire (recherche web, sept. 2026)

Hypothèse posée plus haut à vérifier : Codex CLI a beaucoup évolué depuis la
conception de ce kit et a maintenant des équivalents à trois des quatre
briques Claude Code — mais pas au même endroit ni sous la même forme, et
**rien de tout ça n'a été testé en conditions réelles sur ce repo**, seulement
trouvé dans la doc publique.

| LoopKit (Claude Code) | Équivalent Codex CLI | Où | Portable ? |
| --- | --- | --- | --- |
| `.claude/hooks/*.sh` (PreToolUse qui refuse — `tdd-require-red`, `enforce-architecture`, `no-any`…) | **Hooks Codex** : mêmes événements (`PreToolUse`, `PostToolUse`, `SubagentStart/Stop`…), même mécanique de refus (JSON `permissionDecision: "deny"` ou `exit 2` + stderr) | `config.toml` (`~/.codex/` ou projet), blocs `[[hooks.PreToolUse]]` avec `matcher` + `command` | **Probablement, à confirmer** — le nom des tools Codex diffère (`apply_patch` au lieu de `Write`/`Edit`), donc `matcher` et le schéma JSON exact sont à adapter, pas un copier-coller garanti |
| `.claude/skills/*` (`SKILL.md` name+description+scripts/references) | **Skills Codex**, structure quasi identique | `.agents/skills/<nom>/SKILL.md` (+ `scripts/`, `references/`, `assets/`, `agents/openai.yaml` pour la politique d'invocation) | **Oui, structurellement proche** — juste un chemin différent |
| `.claude/rules/*.md` + imports `@` dans `CLAUDE.md` | **Rien d'équivalent** — hiérarchie `AGENTS.md` seule (un par dossier, le plus proche gagne, concaténés, plafond 32 Kio), pas d'imports | — | **Non portable tel quel**, mais pas un manque réel : `AGENTS.md` du repo demande déjà à Codex de lire `CLAUDE.md` puis les règles pertinentes via son outil de lecture — c'est le contournement correct |
| `.claude/agents/*.md` (`reviewer`, `test-writer`…) | **Sous-agents custom Codex**, propre modèle/sandbox/MCP/instructions | `.codex/agents/*.toml` (projet) ou `~/.codex/agents/` (global) | **Oui dans l'esprit**, format différent (TOML vs Markdown+frontmatter) — retraduction agent par agent, pas automatique |

**Conséquence sur ce plan** : la ligne 47 du tableau "Qui fait quoi" et la
"Nuance importante" ci-dessus affirment que le cycle RED ne peut pas bouger
vers Codex faute de hooks équivalents. Si les hooks Codex interceptent
vraiment `apply_patch` avec la même sémantique de refus, cette hypothèse
tombe et le levier "EXECUTE — RED en plus" (écarté plus bas comme
`Ne pas faire`) mérite d'être retesté. **Ne pas basculer là-dessus sans un
test concret** : porter un seul hook (ex. `tdd-require-red.sh` — celui qui
bloque réellement, en `PreToolUse` ; `tdd-prove-red.sh` n'observe qu'après
coup, en `PostToolUse`, cf. section suivante) dans `.codex/config.toml`,
déclencher un vrai `apply_patch` côté Codex sur ce repo, et vérifier qu'il
refuse comme le hook Claude le ferait. Tant que ce test n'a pas tourné, le
tableau plus bas garde `Ne pas faire` par prudence.

Sources (à revalider le jour de l'implémentation, Codex CLI change vite) :
[Hooks](https://learn.chatgpt.com/docs/hooks) ·
[Build skills](https://learn.chatgpt.com/docs/build-skills) ·
[AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) ·
[Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) ·
[openai/codex skills.md](https://github.com/openai/codex/blob/main/docs/skills.md)

### Confirmation (recherche complémentaire) — c'est bien supporté au niveau projet

Trois faits vérifiés en plus, sourcés :

- **Les hooks projet existent vraiment** : `<repo>/.codex/config.toml` avec une
  table `[hooks]` (ou `[[hooks.PreToolUse]]`), **committée dans le repo**,
  chargée par Codex en marchant de la racine du projet vers le dossier
  courant. Condition : le projet doit être **"trusted"** dans la config Codex
  de l'utilisateur — un geste ponctuel, pas un blocage permanent, mais une
  étape de setup à documenter.
- **`PreToolUse` ne fait que refuser, jamais modifier/mettre en pause** — exactement
  ce dont `tdd-require-red` a besoin (il bloque ou laisse passer la création du
  fichier d'implémentation, il ne réécrit jamais l'écriture). `tdd-prove-red`,
  lui, n'a pas besoin de refuser : il observe le run de tests *après* l'écriture
  et pose un marqueur — côté Claude il est câblé en `PostToolUse`
  (`.claude/settings.json:118-139`), pas en `PreToolUse`. Le porter côté Codex
  suppose donc un événement post-écriture équivalent, pas le même bloc
  `[[hooks.PreToolUse]]` que `tdd-require-red`.
- **Pas de `CODEX_PROJECT_DIR`** — Codex ne pose aucune variable d'environnement
  équivalente à `CLAUDE_PROJECT_DIR` ; le contexte arrive par le JSON stdin,
  champ `cwd`. Bonne nouvelle en pratique : `tdd-require-red.sh:63` et
  `tdd-prove-red.sh:65` font déjà toutes les deux
  `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"` — tant que Codex exécute la commande
  du hook avec `cwd` = racine du repo (ce qui est l'hypothèse la plus probable),
  ce fallback suffit **sans toucher aux scripts**.
- **Le vrai inconnu, pas résolu par la doc publique** : `tdd-require-red.sh:46`
  et `tdd-prove-red.sh:49` lisent toutes les deux `.tool_input.file_path` — un
  seul fichier par appel, comme `Write`/`Edit` côté Claude. Le payload
  `apply_patch` de Codex peut regrouper **plusieurs fichiers dans un seul
  patch** ; si c'est le cas, `.tool_input.file_path` n'existe probablement pas
  sous cette forme et le script échoue silencieusement (jq renvoie vide,
  `// empty`). **Ça ne se résout pas en lisant la doc, il faut un payload
  réel.**

Sources : [Codex CLI Hooks Reference](https://agenticcontrolplane.com/blog/codex-cli-hooks-reference) ·
[Codex CLI Permissions, Hooks & Audit Log](https://agenticcontrolplane.com/integrations/codex) ·
[Deploy hooks for Codex — Endor Labs](https://docs.endorlabs.com/agent-governance/codex/index) ·
[Async Hooks and MCP Tool Hooks in Codex CLI v0.148.0](https://codex.danielvaughan.com/2026/08/25/codex-cli-v0148-async-hooks-mcp-tool-hooks-background-execution-mcp-integration/)

### POC hooks — le test concret avant de rouvrir quoi que ce soit

Un seul hook, pas les 18. Le plus révélateur pour la question posée ("un hook
Codex peut-il refuser une écriture comme le fait Claude Code") :
`tdd-require-red.sh` — c'est lui qui bloque réellement la création du fichier
d'implémentation (il lit `.tool_input.file_path`, teste l'existence d'un
marqueur, refuse ou laisse passer), pas `tdd-prove-red.sh` qui n'observe
qu'après coup et ne refuse jamais rien lui-même (cf. section précédente). S'il
porte, les hooks de refus statique comme `no-any`/`enforce-architecture`
portent presque sûrement aussi — même mécanique, condition plus simple.

**Portée du POC** : ça prouve que `PreToolUse` peut refuser côté Codex et que
le payload expose bien le chemin de fichier attendu. Ça ne prouve pas encore
le cycle RED complet — pour ça il faudrait en plus porter `tdd-prove-red.sh`
sur un événement post-écriture équivalent (s'il existe côté Codex) et vérifier
qu'il pose bien son marqueur ; hors scope de ce POC minimal, à faire seulement
si celui-ci passe.

Câblage actuel côté Claude, pour référence exacte —
`.claude/settings.json:60-73` environ, bloc `PreToolUse` avec
`matcher: "Write|Edit"`, `command: "$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-require-red.sh"`
(à distinguer du bloc `PostToolUse`, `.claude/settings.json:118-139`, qui
câble `tdd-prove-red.sh` — même matcher `Write|Edit`, événement différent).

Étapes du POC :

1. **Faire confiance au projet** côté Codex (étape de setup ponctuelle,
   nécessaire avant que `.codex/config.toml` du repo soit même lu).
2. **Capturer un payload réel avant de brancher quoi que ce soit** : un hook
   jetable qui ne fait que `cat > /tmp/codex-hook-payload.json` sur son stdin,
   déclenché sur un `apply_patch` réel touchant un seul fichier. Lire ce
   fichier pour savoir si le chemin arrive bien sous `.tool_input.file_path`
   (comme Claude) ou sous une autre forme (liste de fichiers, diff brut) —
   c'est la seule inconnue qui ne se résout pas en lisant la doc.
3. Si le payload est compatible (ou une fois l'adaptateur minimal écrit) :
   dans `.codex/config.toml` (projet, committé) :
   ```toml
   [[hooks.PreToolUse]]
   matcher = "apply_patch"

   [[hooks.PreToolUse.hooks]]
   type = "command"
   command = ".claude/hooks/tdd-require-red.sh"
   timeout = 30
   ```
   Chemin relatif au repo — pas besoin de variable d'environnement type
   `CLAUDE_PROJECT_DIR`, le script retombe déjà sur `.`
   (`tdd-require-red.sh:63`), et Codex exécute la commande avec `cwd` = racine
   du projet.
4. Lancer Codex sur ce repo, lui faire écrire (créer, pas éditer) un fichier
   test-first minimal sans red préalable prouvé (donc sans marqueur), et
   vérifier que le refus arrive — même message, même blocage qu'avec Claude.
5. Si ça marche : masse critique franchie sur la moitié "refus" du cycle RED ;
   reste à vérifier séparément la moitié "observation" (`tdd-prove-red.sh` en
   post-écriture) avant de rouvrir le levier dans le tableau coût/bénéfice.
   Porter les skills (`.agents/skills/`) et les hooks restants **hors les
   quatre du §"Garde-fous non-TDD" ci-dessous** devient un chantier à part, pas
   dans ce plan-ci — trop gros pour être mélangé à la bascule Claude/Codex du
   loop. Si ça ne marche pas : le "Ne pas faire" de la ligne RED reste tel
   quel, referme le sujet sans y revenir à chaque plan — mais le §"Garde-fous
   non-TDD" reste dû quand même, lui, puisqu'il ne dépend pas du cycle RED.

**Résultat (exécuté le 2026-09-07, `codex-cli 0.147.0`, modèle `gpt-5.6-sol`,
projet déjà `trust_level = "trusted"` dans `~/.codex/config.toml`) : ÉCHEC.**

Étapes réellement suivies : 1 (déjà acquis — projet trusted) ; 2 (hook jetable
`cat > /tmp/codex-hook-payload.json` sur `matcher = "apply_patch"` dans un
`.codex/config.toml` du repo) ; 4 (`codex exec -s workspace-write "Create a new
file ..."` sur un fichier scratch hors `src/`/`shared/`, hors TDD).

Deux faits vérifiés, indépendants l'un de l'autre — chacun suffit seul à
invalider la config proposée plus haut :

1. **`matcher = "apply_patch"` ne correspond à aucun tool call réel.** Le log
   debug (`RUST_LOG=codex=debug`) montre que ce build (feature `CodeModeHost`
   active) ne fait pas de `apply_patch` un tool call de premier niveau : le
   modèle passe par `exec const r = await tools.apply_patch("*** Begin
   Patch...")` — un tool nommé `exec` (même famille que `Bash`/`exec_command`)
   qui *appelle* `apply_patch` comme fonction JS interne. Un hook côté Codex
   devrait donc matcher `exec` et parser le payload JS pour en extraire le
   patch, pas juste lire `.tool_input.file_path` comme le fait
   `tdd-require-red.sh` — un portage bien plus lourd que "brancher le script
   Claude tel quel" envisagé plus haut.
2. **Même avec `matcher = ".*"` (catch-all), le hook n'a jamais été invoqué —
   aucun payload capturé, deux exécutions de suite, fichier créé sans
   interception.** L'option `--dangerously-bypass-hook-trust` ("Run enabled
   hooks without requiring persisted hook trust") indique que les hooks
   exigent une confiance persistée établie ailleurs qu'un simple `trust_level`
   de projet — vraisemblablement une invite interactive côté TUI, jamais
   déclenchée par `codex exec` non-interactif, qui semble alors ignorer les
   hooks silencieusement plutôt que les bloquer. Tenter le flag de contournement
   a été refusé par le classifieur de sécurité de la session Claude Code elle-
   même (nom de flag jugé dangereux) — abandonné plutôt que contourné,
   conformément à l'usage prévu du flag ("automation that already vets hook
   sources", pas une bascule à la légère). Accorder cette confiance suppose une
   action humaine interactive (`codex` en TUI dans ce repo) hors de portée
   d'une session `codex exec` scriptée.

**Conséquence, tranchée avec l'utilisateur** : le point 1 à lui seul rend la
config du §"POC hooks"/"Garde-fous non-TDD" inopérante telle qu'écrite, et le
point 2 est générique à *tout* hook `PreToolUse` (même famille "refus
statique" que les quatre garde-fous non-TDD, cf. leur propre raisonnement
"s'il porte, ceux-là portent presque sûrement aussi") — pas spécifique au
cycle RED. Verdict : **`Ne pas faire`, confirmé et refermé** — pour le cycle
RED *et* pour les quatre garde-fous non-TDD, pas seulement RED comme la
distinction ci-dessus l'envisageait avant test. **Volet 2 entièrement sauté**
(`.codex/config.toml` non créé/commité, `no-forbidden-icons`/`no-any-type`/
`enforce-architecture`/`english-comments` restent Claude-only). Le filet
`reviewer.md` du §"Garde-fous non-TDD" point 2 (critère icônes interdites dans
la dimension `ui`) reste utile et est traité indépendamment plus bas — il ne
dépendait déjà pas du hook.

### Garde-fous non-TDD — condition avant de confier du vrai code à Codex

Le POC ci-dessus ne teste que le cycle RED. Mais l'"Approche retenue"
(ci-dessous) confie à Codex du vrai code en dehors du test-first :
EXECUTE-GREEN (wiring, DB, composants, backend) et les correctifs REVIEW —
exactement le genre d'écriture que quatre hooks `PreToolUse` **non liés au
TDD** surveillent côté Claude : `no-any-type.sh`, `enforce-architecture.py`,
`no-forbidden-icons.sh`, `english-comments.py`. Le même problème que celui
identifié pour `05-testing.md` (ligne 59-60 : `AGENTS.md` *demande* de lire
les règles, rien ne l'impose comme le hook) s'applique **identiquement** à ces
quatre-là — `AGENTS.md` ne les cite même pas nommément aujourd'hui.

Ce ne sont pas des hooks qui *jugent* un résultat comme `tdd-prove-red` : ce
sont des refus statiques (grep/AST sur le delta), la même famille que
`tdd-require-red` testée par le POC — s'il porte, ceux-là portent presque
sûrement aussi (raison déjà donnée §"POC hooks"). Donc, une fois le POC validé
sur `tdd-require-red.sh`, porter ces quatre hooks dans le même
`.codex/config.toml` est un ajout marginal, pas un second chantier :

```toml
[[hooks.PreToolUse]]
matcher = "apply_patch"

[[hooks.PreToolUse.hooks]]
type = "command"
command = ".claude/hooks/no-any-type.sh"
timeout = 15

[[hooks.PreToolUse.hooks]]
type = "command"
command = ".claude/hooks/enforce-architecture.py"
timeout = 15

[[hooks.PreToolUse.hooks]]
type = "command"
command = ".claude/hooks/no-forbidden-icons.sh"
timeout = 15

[[hooks.PreToolUse.hooks]]
type = "command"
command = ".claude/hooks/english-comments.py"
timeout = 15
```

(Plusieurs `[[hooks.PreToolUse.hooks]]` sous un même `matcher` — à confirmer
contre la doc Codex au moment de l'implémentation ; sinon, un bloc
`[[hooks.PreToolUse]]` par hook avec le même `matcher = "apply_patch"`.)

**En attendant que ce port soit fait et confirmé**, EXECUTE-GREEN et les
correctifs REVIEW ne doivent **pas** partir sur Codex par défaut sans filet :
vérification faite dans `reviewer.md`, la dimension `correctness` couvre déjà
`no any` (ligne ~98) et les limites d'architecture (ligne ~46-50, "you are the
backstop that matters here") — donc ces deux-là ont un rattrapage en Phase 5
même sans hook côté Codex, dégradé (après coup, pas bloquant à l'écriture,
mais pas absent). **`no-forbidden-icons` n'a aucun rattrapage** : ni
`reviewer.md` ni `verifier.md` ne mentionnent icônes/emoji/lucide nulle part
— vérifié par recherche. Un composant écrit par Codex avec une icône
`Star`/`Rocket`/`Zap`/`Bolt` traverserait la Phase 5 sans qu'aucun garde-fou,
hook ou dimension de review, ne le voie.

Deux mesures, pas une seule — le hook reste l'objectif, la dimension de review
est le filet le temps qu'il soit porté et confirmé, pas un remplacement :

1. **Porter le hook** (ci-dessus) — objectif principal, condition de la
   bascule GREEN par défaut.
2. **En attendant, ajouter un critère explicite "icônes interdites" à la
   dimension `ui` de `reviewer.md`** (`09-icons.md` : Star, Stars, Sparkle,
   Sparkles, Rocket, RocketLaunch, Zap, Bolt, LightningBolt + glyphes emoji) —
   coût marginal, et ça referme aussi le trou pour du code écrit par Claude
   lui-même sur un fichier où le hook n'a vu que le delta (même raison que le
   bullet "backstop" déjà présent pour l'archi).

## Où pousser plus loin — analyse coût/bénéfice

Objectif : allonger la durée de vie de l'abonnement Claude sans que Codex
devienne lui-même le goulot (son forfait à 20€ n'est pas illimité non plus —
c'est le point de départ de toute cette discussion). Deux coûts à mettre en
balance à chaque levier candidat :

1. **Ce que ça économise réellement côté Claude** — le vrai poste de coût
   n'est pas le nombre d'agents, c'est le travail **inline sur le fil
   principal** : Phase 4 EXECUTE ("Implement yourself... Do not delegate") et
   la correction des findings en Phase 5 REVIEW sont les deux seuls endroits
   où Claude édite du code en direct sur toute la durée de la feature. Le
   reste (RESEARCH, INTERFACE, PLAN, SHIP) est déjà borné par construction :
   sous-agents à tier bas, batches limités par le profil `economy`. Les
   déplacer économiserait peu.
2. **Ce que ça coûte en aller-retour** — chaque bascule Claude↔Codex a un
   prix fixe (écrire/lire le handoff, toi qui changes d'outil à la main,
   Codex qui relit `AGENTS.md`+`CLAUDE.md`+l'artefact). Multiplier les petites
   bascules sur des étapes déjà bon marché coûte plus cher que ça ne fait
   économiser.

Conclusion du croisement des deux :

**La colonne "Économie Claude" ci-dessous est une estimation qualitative, pas
une mesure** — `docs/work/` n'a encore aucun feature loop complet à analyser,
et `docs/measuring-the-loop.md` prévient que ce genre de pari a un mauvais
historique dans ce kit. À confirmer par un vrai compte avant/après une fois
implémenté, cf. §"Vérification" ci-dessous.

| Levier | Économie Claude | Coût de l'aller-retour | Verdict |
| --- | --- | --- | --- |
| EXECUTE — GREEN/mécanique (déjà retenu) | Élevée — plus gros bloc de code inline | Un seul aller-retour par feature | **Garder** |
| REVIEW — correction des findings déjà tranchés | Élevée — deuxième plus gros bloc de code inline ; le jugement (`reviewer`/`verifier`) reste sur Claude, seule l'écriture du correctif part | Un aller-retour par cycle de review, en général 1 | **Ajouter** — meilleur rapport économie/coût après EXECUTE |
| EXECUTE — RED en plus (`test-writer`) | Faible — déjà un sous-agent borné en `sonnet`, un seul fichier | Perd l'enforcement des hooks TDD, Codex n'a pas d'équivalent opérant | **Ne pas faire** — testé le 2026-09-07, POC échoué (cf. §"POC hooks" étape 5) : `matcher = "apply_patch"` ne matche aucun tool call réel dans ce build, et les hooks `PreToolUse` projet n'ont jamais été invoqués faute de confiance persistée accordable hors TUI interactif |
| `e2e-tester` (Playwright) → Codex | Moyenne, mais déjà borné à 1 agent en economy | Codex doit pouvoir lancer `pnpm dev` + navigateur — complexité d'environnement en plus | **À évaluer plus tard**, pas par défaut |
| RESEARCH / INTERFACE / PLAN → Codex | Faible — déjà des sous-agents bornés à tier bas | Un aller-retour par étape, sur des étapes courtes | **Ne pas faire** |

**Recommandation** : garder EXECUTE-GREEN (déjà dans le plan) et ajouter la
correction des findings REVIEW comme deuxième bascule officielle. C'est le
seul autre endroit où Claude fait un vrai volume d'édition inline, la
frontière jugement/exécution reste la même que pour EXECUTE (Claude tranche,
Codex écrit), et ça reste un aller-retour par review — pas une multiplication
de petites bascules.

## Approche retenue

Répartition par défaut, une fois le plan approuvé (fin de la Phase 3 —
Test Plan Gate) :

- **Claude** garde RESEARCH → INTERFACE → PLAN → le jugement de REVIEW
  (`reviewer`/`verifier`) → SHIP (jugement, proposition, critique
  adversariale — le tier `inherit` de `11-token-budget.md`).
- **Codex** reçoit deux blocs mécaniques, chacun via le mécanisme déjà
  existant (`/handoff:codex` + `codex-handoff.sh`), déclenché
  **délibérément** plutôt que seulement en cas de saturation :
  1. EXECUTE-GREEN (implémentation une fois le plan et les tests gelés), à la
     fin de la Phase 3 ;
  2. la **correction des findings Critical/Major déjà tranchés en REVIEW**
     (Claude a produit le verdict, Codex écrit le correctif), à la fin du
     passage `reviewer`/`verifier` de la Phase 5 — avant le re-run des
     dimensions affectées.

### Routeur déclaratif — sortir "qui pilote quoi" de la prose d'`orchestrate.md`

Aujourd'hui cette décision vit à deux endroits qui peuvent diverger : la table
"Qui fait quoi dans le workflow" (tout en haut de ce document) et les branches
`command -v codex` qu'"Fichiers à modifier" propose d'écrire en dur dans
`orchestrate.md`. Un fichier déclaratif évite la divergence et rend la bascule
future (un autre CLI, ou revenir tout sur Claude) éditable sans toucher à la
commande :

```yaml
# .claude/workflow-routing.yml
# Pilote par rôle. Codex n'est éligible qu'aux deux rôles mécaniques retenus
# ci-dessus (execute-green, review-fixes) — le reste reste sur Claude par
# construction : les sous-agents `.claude/agents/*.md` ne sont invocables que
# depuis une session Claude (cf. "Qui fait quoi dans le workflow" en tête de
# ce document). `provider: codex` reste une PRÉFÉRENCE, pas une garantie —
# `orchestrate.md` teste toujours `command -v codex` au moment de basculer et
# retombe sur Claude s'il est absent (§"Repli dans les deux sens", point 1,
# inchangé). `codex_effort` n'a de sens que si `provider: codex` — cf.
# §"Économie côté Codex" plus bas, présent ici pour que le fichier ait un
# seul schéma, pas deux formes selon le pilote.
roles:
  research:        { provider: claude }
  interface:        { provider: claude }
  plan:              { provider: claude }
  execute-red:      { provider: claude }
  execute-green:    { provider: codex, codex_effort: low }
  review-judgment:  { provider: claude }
  review-fixes:      { provider: codex, codex_effort: low }
  ship:              { provider: claude }
```

`orchestrate.md` lit ce fichier au lieu d'embarquer le test dans sa prose :
absent → tout sur Claude (comportement actuel, aucune régression). Une ligne
change ici, pas la commande, le jour où l'un des deux abonnements passe devant
l'autre — c'est exactement l'argument qui justifie ce fichier plutôt qu'un
`if` de plus dans `orchestrate.md`. Les tiers de modèle Claude
(`11-token-budget.md`) restent un axe séparé et ne bougent pas : ce fichier ne
dit que "Claude ou Codex", jamais "quel tier Claude" — les deux répartitions
restent orthogonales comme la section d'ouverture le dit déjà.

### Repli dans les deux sens

1. **Codex absent du PATH** → on saute simplement la bascule et Phase 4
   s'exécute inline sur Claude, exactement comme aujourd'hui. Aucun nouveau
   code : juste une condition documentée (`command -v codex`).
2. **Claude à sa limite** → déjà automatique (`workflow.py`), inchangé.
3. **Codex à sa limite / en échec pendant EXECUTE** (nouveau — pas détectable
   automatiquement, c'est un process externe) → protocole de reprise manuel :
   l'utilisateur revient sur Claude et relance
   `/loop:orchestrate docs/work/<slug>/plan.md`. Pour que la reprise soit
   correcte (ne pas refaire tout EXECUTE, ni sauter à REVIEW à tort), il faut
   que l'état sur disque soit à jour des deux côtés :
   - `AGENTS.md` doit demander à Codex de rafraîchir
     `docs/work/<slug>/handoff-codex.md` après chaque étape/couche TDD
     terminée — symétrique à ce qu'`orchestrate.md` demande déjà à Claude
     ("Automatic checkpoints").
   - `orchestrate.md` Phase 0 étape 1 doit lire ce `handoff-codex.md` s'il
     existe pour décider d'entrer en Phase 4 (reprise en cours) ou Phase 5
     (EXECUTE déjà terminé) au lieu de sauter systématiquement en Phase 4 sur
     tout `plan.md`.
   - **Vérifié, ne suffit pas tel quel** : `Current phase` dans le template
     de `/handoff:codex` (`.claude/commands/handoff/codex.md:28`) n'a que 6
     valeurs — `research | interface | plan-gate | execute | review | ship` —
     pas assez fin pour la décision à 3 branches que ce point demande (reprise
     Phase 4 / Phase 5-jugement / Phase 5-correctifs déjà tranchés en attente
     du retour Codex). `orchestrate.md` rafraîchit déjà le checkpoint "after
     ... each completed RED→GREEN layer, review fixes, and ship gates"
     (§"Automatic checkpoints") — la granularité existe déjà dans les sections
     `## In progress`/`## Remaining` en texte libre, juste pas dans une forme
     qu'une routine automatique peut lire sans reparser de la prose.
   - **Un statut en frontmatter YAML plutôt qu'une énumération qui grossit
     en ligne** : au lieu d'étendre `Current phase` en valeurs composées
     (`execute-done`, `review-fixes-handed-to-codex`...), donner à
     `handoff-codex.md` un petit bloc structuré en tête, séparé de la prose
     qui reste faite pour être lue par un humain ou par Codex, pas parsée
     par une routine :
     ```yaml
     ---
     phase: execute        # research | interface | plan-gate | execute | review | ship
     execute_status: in-progress   # in-progress | done — n'a de sens que si phase: execute
     review_status: judgment       # judgment | fixes-handed-to-codex | fixes-done — n'a de sens que si phase: review
     token_profile: economy
     ---
     ```
     `phase` reste l'énumération à 6 valeurs, inchangée — la nuance que ce
     plan demandait vit dans `execute_status`/`review_status`, deux champs à
     un seul sens chacun plutôt qu'un enum combinatoire. Phase 0 route sur
     trois lectures triviales plutôt qu'un `if` sur des chaînes composées :
     `phase: execute` + `execute_status: in-progress` → reprise Phase 4 ;
     `execute_status: done` (ou `phase: review` sans `review_status` encore
     posé) → Phase 5-jugement ; `review_status: fixes-handed-to-codex` →
     reprise du re-run des dimensions affectées, pas un jugement REVIEW repris
     de zéro. Fichiers à modifier en conséquence : `.claude/commands/handoff/codex.md`
     (le template, frontmatter en tête + `AGENTS.md`/"Automatic checkpoints"
     mis à jour pour l'écrire) — actuellement absent de la liste "Fichiers à
     modifier" ci-dessous.

## Plan de réattribution des tiers de modèles (agents Claude)

Volet complémentaire, indépendant de la bascule Codex mais qui vise le même
but : équilibrer coût et performance en descendant les agents qui ne font que
produire à partir d'une entrée déjà validée, et en montant celui dont une
erreur silencieuse se propage dans tout le reste de la loop.

**Principe** : un agent descend de tier quand son entrée est déjà validée en
amont (il produit, il ne tranche pas). Un agent monte quand sa sortie est
consommée par tout le reste du loop et qu'une erreur s'y propage
silencieusement. Les 5 gates restent en `inherit` — "A gate never runs below
the session model" (`11-token-budget.md`) reste vrai tel quel, aucune
réécriture de règle au-delà de la table.

| Agent | Actuel | Cible | Sens | Raison |
| --- | --- | --- | --- | --- |
| `reviewer` | inherit | inherit | = | gate, peut bloquer un ship |
| `verifier` | inherit | inherit | = | gate, décide si un finding survit |
| `story-critic` | inherit | inherit | = | gate, juge le découpage |
| `plan-critic` | inherit | inherit | = | gate, dernier filet avant EXECUTE |
| `security-auditor` | inherit | inherit | = | gate, coût d'un faux négatif trop élevé |
| `test-writer` | inherit | sonnet | baisse | écrit 1 fichier depuis un plan de test déjà validé, le hook `tdd-prove-red` vérifie le résultat |
| `e2e-tester` | inherit | sonnet | baisse | traduit des critères d'acceptation en spec Playwright, la spec passe ou casse |
| `github` | inherit | sonnet | baisse | staging, commits, messages courts, la validation humaine gate le remote |
| `designer` | inherit | sonnet | baisse | en economy et standard le juge tourne sur le main thread, l'agent ne fait que proposer |
| `story-writer` | haiku | sonnet | montée | les stories alimentent architecture, plans et features, une story mal découpée coûte plusieurs boucles |
| `explorer` | haiku | haiku | = | cartographie read-only, extraction bornée |
| `doc-researcher` | sonnet | sonnet | = | déjà au bon tier |

Répartition finale : 5 `inherit`, 6 `sonnet`, 1 `haiku`.

**Réserve sur `designer`** : un seul champ `model:` couvre les deux modes. En
`critical`, `/loop:interface` lance un `designer` supplémentaire en mode juge,
qui tomberait donc aussi en `sonnet`. Deux options : (1) accepter — le juge
critical redevient une proposition parmi d'autres validée par l'utilisateur ;
(2) garder `designer` en `inherit` et ne descendre que les trois autres.
Option 1 retenue ; si les arbitrages UI deviennent mous en critical,
`designer` remonte — c'est une ligne à changer, pas un plan à refaire.

### Application

**1. La table de la règle** — `.claude/rules/11-token-budget.md`, section
`## Model tiers`. Remplacer les trois lignes par :

```
| `inherit` | gates: judgement that can stop the loop | `reviewer`, `verifier`, `story-critic`, `plan-critic`, `security-auditor` |
| `sonnet` | bounded production from a validated entry, and external-doc relevance | `doc-researcher`, `story-writer`, `test-writer`, `e2e-tester`, `designer`, `github` |
| `haiku` | bounded extraction/transcription | `explorer` |
```

Le fichier fait 37 lignes pour un budget de 55 : la table ne grossit pas, rien
à compenser ailleurs. **Attention au parseur de `kit-doctor.py`** : il ne lit
que la dernière cellule de chaque ligne pour trouver les agents — aucun nom
d'agent entre backticks dans la colonne du milieu, il serait affecté au
mauvais tier.

**2. Les frontmatters** :

```bash
cd .claude/agents
sed -i 's/^model: inherit$/model: sonnet/' test-writer.md e2e-tester.md github.md designer.md
sed -i 's/^model: haiku$/model: sonnet/' story-writer.md
```

**3. Vérification** :

```bash
python3 .claude/hooks/kit-doctor.py
```

Attendu sur la ligne `agent-models` : `OK` — 12 agents avec le décompte
`inherit` 5, `sonnet` 6, `haiku` 1. Toute divergence veut dire que la table et
les frontmatters ne disent pas la même chose — c'est exactement ce que ce
check existe pour attraper.

**Figer la version** : `sonnet` est un alias qui suivra la prochaine
génération. Pour rester sur Sonnet 5 quoi qu'il arrive, écrire
`claude-sonnet-5` partout (frontmatters + colonne tier de la table) — les deux
copies doivent être strictement identiques, le parseur accepte le format
(minuscules, chiffres, tirets). Recommandation : garder l'alias — le kit est
public, un pin de version le fait vieillir plus vite qu'il ne le protège.

**Après** — faire tourner une feature complète en profil `economy` et
regarder deux chiffres précis, qui décident si le plan tient :

1. `test-writer` en `sonnet` passe-t-il toujours `tdd-prove-red` du premier
   coup, ou multiplie-t-il les allers-retours au RED (si oui, la baisse a
   coûté plus qu'elle n'a économisé, il remonte) ;
2. la qualité des stories après la montée de `story-writer`, mesurée par le
   nombre de findings que `story-critic` remonte.

## Économie côté Codex — ne pas rouler en effort maximal par défaut

Volet symétrique au précédent, côté Codex cette fois. Même principe — faire
correspondre le coût au rôle, jamais "le meilleur modèle pour tout" — mais un
axe différent : pas un choix de modèle Claude (`inherit`/`sonnet`/`haiku`),
l'effort de raisonnement Codex, qui répond à la même logique
mécanique-vs-jugement établie plus haut.

**Deux situations, pas la même exigence** :

1. **Bascule délibérée** (`execute-green`, `review-fixes` — Claude toujours
   disponible) : Codex ne fait que du mécanique borné, jamais de jugement —
   c'est la définition même de ce que ce plan lui confie (§"Approche
   retenue"). Un effort bas suffit ; le payer en effort maximal serait
   acheter un jugement que personne ne lui demande.
2. **Relais complet** (Claude à sa limite, §"Repli dans les deux sens" point
   2 — mécanisme existant `workflow.py`, inchangé, toujours affecté par
   W-01/W-05/W-11) : Codex hérite de **tout** ce qui reste dans la loop, y
   compris des rôles que Claude gardait pour lui — arbitrage interface,
   critique de plan, verdict REVIEW, sécurité. Là, un effort uniformément bas
   serait l'erreur symétrique de "tout en `inherit`" côté Claude : dégrader le
   jugement au moment précis où plus personne d'autre ne le fait. Et rouler
   tout en effort maximal par défaut — la question posée — gaspille sur les
   étapes qui restent mécaniques même pendant un relais complet (bookkeeping
   du checkpoint, lancer les gates, mise à jour du board).

### Ce qu'on sait de la tiering Codex (recherche web, sept. 2026 — corrigé une
fois en écrivant ce paragraphe, cf. note de bas)

Codex CLI expose un axe **modèle** et un axe **effort de raisonnement**,
orthogonaux, sur le même principe que ce plan applique déjà côté Claude :

- **Modèles, prix réels (sept. 2026)** — la famille en place, GPT-5.6, a
  trois tiers, du moins cher au plus cher : **Luna** ($0,20 / $1,20 par
  million de tokens entrée/sortie — le plus rapide, le moins cher), **Terra**
  ($2 / $12 — équilibré), **Sol** ($4 / $20 — flagship, seul tier avec
  l'effort `max` et un mode "ultra" à sous-agents parallèles natifs). Un
  facteur **20×** sépare Luna de Sol — c'est le vrai levier économique, plus
  gros que l'effort de raisonnement à modèle constant.
- **`model_reasoning_effort`** : `minimal | low | medium | high | xhigh` —
  `xhigh`/`max` réservés au tier haut de gamme (Sol) ; un effort choisi peut
  donc contraindre silencieusement quel modèle a un sens pour un profil
  donné. Modèle et effort restent deux réglages séparés : Luna/Terra
  acceptent probablement un sous-ensemble de la plage d'effort, à confirmer.
- **Réglage** : `~/.codex/config.toml` (ou le `.codex/config.toml` projet déjà
  utilisé pour les hooks, §"Confirmation") porte un modèle et un effort par
  défaut ; `--model`/`-m`, `-e`, ou `-c model_reasoning_effort=<niveau>`
  surchargent par invocation.
- **Piège de version, à vérifier au moment de l'implémentation** : des
  profils nommés (`[profiles.<nom>]` dans `config.toml`, bundle modèle +
  effort) existaient, mais à partir de Codex 0.134.0 `--profile` ne lit plus
  ces tables — chaque profil vit dans son propre fichier
  (`~/.codex/deep.config.toml` par ex.). Parier sur un bloc `[profiles.x]`
  dans `.codex/config.toml` n'est donc **pas robuste aux versions**.
- **La famille change sous nos pieds, la preuve par l'exemple plutôt que
  l'avertissement abstrait** : la première passe de recherche pour ce
  paragraphe a trouvé `gpt-5.1-codex-mini`/`gpt-5.1-codex-max` comme famille
  courante. Une deuxième passe, dans la même session, a trouvé GPT-5.6
  (Sol/Terra/Luna, GA le 9 juillet 2026) comme famille **déjà standard**, et
  une troisième a trouvé Codex CLI 0.153.4 (4 septembre 2026) faisant de
  **GPT-6 Astra** le nouveau défaut embarqué — avec une note explicite que
  l'accès à Astra reste inégal selon les comptes, et que GPT-5.6 Sol
  ("Power", effort medium) reste le repli stable recommandé en attendant.
  Trois familles trouvées en trois recherches successives le même jour : ne
  **jamais** figer un nom de modèle en dur dans
  `.claude/workflow-routing.yml` ou `codex-handoff.sh` — utiliser les niveaux
  symboliques (`low`/`medium`/`high`, ou "le moins cher disponible") et
  laisser Codex résoudre le nom réel via son propre défaut/config, jamais une
  chaîne comme `gpt-5.1-codex-mini` écrite dans ce plan.

Sources : [GPT-5.6 pricing: Sol, Terra and Luna rates](https://www.eesel.ai/blog/gpt-5-6-pricing) ·
[GPT-5.6 Sol, Terra & Luna: Tiers & Pricing](https://codersera.com/blog/gpt-5-6-sol-terra-luna/) ·
[Codex 0.153.4 makes GPT-6-Astra the default](https://ccleaks.com/news/codex-0-153-4-astra-default-sep-2026) ·
[Codex CLI 0.153.4 Release notes](https://chatgptaihub.com/codex-cli-0-153-4-gpt-6-astra-default-bedrock-routes-async-clarifications) ·
[Model Selection in Codex CLI](https://codex.danielvaughan.com/2026/03/26/codex-cli-model-selection/) ·
[Reasoning Effort Tuning](https://codex.danielvaughan.com/2026/03/27/reasoning-effort-tuning/)

### Proposition

Plutôt que parier sur des profils `config.toml` (piège de version ci-dessus),
injecter l'effort **par invocation**, sur la même commande que
`codex-handoff.sh` imprime déjà — robuste au changement de mécanisme de
profils, et lisible au même endroit que la commande elle-même :

1. **Bascule délibérée** — le champ `codex_effort` déjà posé dans
   `.claude/workflow-routing.yml` (§"Routeur déclaratif") : `low` pour
   `execute-green` et `review-fixes`, cohérent avec "mécanique borné,
   jamais de jugement". `codex-handoff.sh` lit ce champ et ajoute `-c
   model_reasoning_effort=low` (ou l'équivalent confirmé au moment de
   l'implémentation) à la commande qu'il imprime.
2. **Relais complet** — pas un bucket par phase entière (une phase comme
   RESEARCH mélange déjà `explorer` en `haiku` et `doc-researcher` en
   `sonnet` — aucun des deux n'est du jugement, donc "RESEARCH → high" serait
   faux dès la première ligne). La bonne granularité est le **rôle**, pas la
   phase — en reprenant tel quel le tier que "Plan de réattribution des tiers
   de modèles" assigne déjà à chaque sous-agent Claude, avec une seule règle
   de correspondance :

   `inherit → high` · `sonnet → low` · `haiku → minimal`

   | Rôle Claude (tier, table ci-dessus) | Ce que Codex couvre seul pendant le relais | Effort |
   | --- | --- | --- |
   | `explorer` (`haiku`) | cartographie/lecture read-only bornée | `minimal` |
   | `doc-researcher` (`sonnet`) | recherche documentaire externe bornée | `low` |
   | `designer` (`sonnet`) | proposition(s) d'interface | `low` |
   | `plan-critic` (`inherit`) | critique du plan avant EXECUTE | `high` |
   | `reviewer` / `verifier` (`inherit`) | trouver et réfuter des findings REVIEW | `high` |
   | `e2e-tester` (`sonnet`) | spec Playwright depuis les critères d'acceptation | `low` |
   | `github` (`sonnet`) | staging / commit / messages | `low` |
   | `security-auditor` (`inherit`, si `critical`) | audit sécurité | `high` |
   | `story-critic` (`inherit`, hors `/loop:orchestrate`) | critique du découpage en stories | `high` |
   | `story-writer` (`sonnet`, hors `/loop:orchestrate`) | écriture de stories depuis un PRD | `low` |
   | EXECUTE-GREEN / correctifs (jamais un sous-agent, déjà inline côté Claude) | implémentation / correctif mécanique | `low` |
   | Bookkeeping (checkpoint, board, lancer les gates — jamais un sous-agent) | idem | `minimal` |

   **Pourquoi `story-critic`/`story-writer` apparaissent alors que ce plan
   porte sur `/loop:orchestrate`** : `workflow.py` n'est pas scopé à cette
   commande — le relais se déclenche sur la limite de la session Claude, quel
   que soit ce qui tournait (`/stories:review`, `/bmad:sm`…). La table
   ci-dessus doit donc couvrir tous les sous-agents Claude, pas seulement ceux
   de la loop — c'est un oubli corrigé ici, pas une extension de portée
   délibérée.

   `AGENTS.md` doit porter cette table (rôle → effort, pas phase → effort)
   pour que Codex sache s'auto-ajuster pendant un relais complet — un `-c`
   unique sur la commande de lancement ne suffit plus ici, puisque Codex
   change de rôle plusieurs fois dans la même session, contrairement à la
   bascule délibérée qui reste à effort fixe pour toute la durée d'une
   invocation.

**Ce qui reste non résolu, à ne pas trancher ici** : ce plan ne fixe pas les
valeurs exactes (`low` vs `medium`, quel tier de modèle par effort) sans un
test réel — même prudence que le reste du document face à des faits Codex non
vérifiés sur ce repo, et particulièrement méritée ici vu le rythme auquel la
famille de modèles a changé pendant la seule recherche de ce paragraphe. Le
tableau ci-dessus est un point de départ à confirmer, pas une
recommandation figée.

## Sonde kit-health — mesurer au lieu de deviner, une fois pour toutes

Volet indépendant des deux précédents, mais qui sert directement ce plan :
plusieurs bullets de "Vérification" (plus bas) demandent de compter des
choses à la main — les allers-retours RED de `test-writer`, les findings de
`story-critic`, le nombre d'`Edit`/`Write` inline avant/après la bascule
Codex. Une sonde qui enregistre ces événements au moment où ils se produisent
transforme ces comptages manuels, ponctuels, en une requête sur un fichier
qui s'accumule — installée une fois avec le kit, elle sert cette
vérification-ci et toutes les suivantes.

**Portée : strictement locale au projet.** Aucun appel réseau, aucune donnée
qui sort du repo — cohérent avec le reste du kit (hooks, `attempts.json`,
`docs/audits/`, tout ce qu'on a vu jusqu'ici est local).

### Ce qui existe déjà, dispersé

- `docs/work/<slug>/attempts.json` (`kit-attempts.py`) — passe/échoue/retry
  par gate, mais **par feature** : abandonné une fois le feature shippé, pas
  de mémoire au-delà.
- `.claude/.hook-timings.log` — durée d'exécution des hooks, mais pas *ce
  qu'ils ont décidé* (refus ou laissé passer).
- `docs/audits/workflow.md` — le seul précédent de registre **durable et
  diffable** du kit (c'est là que vivent W-01/W-05/W-11), rempli à la main
  lors d'un audit, pas automatiquement.
- `/kit:doctor` (`.claude/hooks/kit-doctor.py`) — la seule commande qui tourne
  déjà en check périodique de santé du kit ; ses `CHECKS` sont aujourd'hui
  tous des comparaisons "la règle dit X, le fichier dit Y" (des jumeaux qui
  doivent s'accorder), pas des résumés de données accumulées — nuance pour
  la proposition ci-dessous.

Rien aujourd'hui ne relie "ce qui bloque" (hooks), "ce qui échoue" (gates) et
"ce que review trouve" dans une mémoire qui survit à une feature.

### Proposition

1. **`.claude/.kit-health.jsonl`** (nouveau, gitignoré — même statut que
   `.claude/.hook-timings.log`, donnée machine locale, pas du code source) :
   une ligne JSON par événement, écrite par le code qui émet déjà le signal
   — pas un nouveau mécanisme, juste lui apprendre à ajouter une ligne de
   plus :
   - `kit-attempts.py` : une ligne à chaque `record()`/`clear()` (gate,
     résultat, feature).
   - Les hooks qui refusent (`tdd-require-red.sh`, `no-any-type.sh`,
     `enforce-architecture.py`, `no-forbidden-icons.sh`,
     `english-comments.py`, `prevent-destructive-commands.sh`…) : une ligne
     quand ils refusent réellement — pas à chaque invocation, seulement au
     refus, sinon le fichier grossit sans rien dire d'utile.
   - La boucle REVIEW : une ligne par finding, avec son verdict
     (`verifier` confirme ou réfute) — la donnée qui répondrait directement à
     "quelle dimension trouve du réel vs du bruit", jamais mesurée
     aujourd'hui.
2. **`/kit:doctor` gagne une nouvelle catégorie `health`** (aux côtés de
   `twins`/`budget`/`wiring`/`links`/`placeholders`, cf.
   `.claude/hooks/kit-doctor.py:1034`) avec un `check_kit_health()` qui lit
   `.claude/.kit-health.jsonl` et résume : quel gate échoue le plus souvent,
   quel hook refuse le plus, quelle dimension REVIEW confirme le plus de
   findings vs en voit réfuter. **Nuance à trancher à l'implémentation** :
   ce n'est pas un "jumeau" comme les autres checks (rien à comparer à une
   règle, juste un résumé de données) — voir si `OK`/`DIVERGENCE`/`MISSING`
   (les sévérités existantes, `.claude/hooks/kit-doctor.py:35`) suffisent
   pour porter un résumé, ou si `check_kit_health` a besoin d'un style de
   `Finding` légèrement différent (informatif, pas verdictif).

**Alternative plus simple, si le jsonl + résumé est jugé trop pour
commencer** : un registre markdown écrit à la main façon
`docs/audits/workflow.md` — lisible tout de suite sans outillage, mais pas
interrogeable ("quel gate échoue le plus" veut dire relire à l'œil). Pas
retenue ici, mais à garder en tête si le jsonl s'avère plus cher à maintenir
que ce qu'il rapporte.

### Ce que ça change dans "Vérification" de ce plan

Une fois construite, la sonde répond directement à trois bullets de
"Vérification" ci-dessous qui demandent aujourd'hui un comptage manuel :
l'économie Claude (§"Où pousser plus loin"), les allers-retours RED de
`test-writer`, et les findings de `story-critic` — cf. les bullets
correspondants, mis à jour pour citer la sonde comme méthode de mesure une
fois qu'elle existe, le comptage manuel restant la méthode tant qu'elle
n'existe pas.

## Fichiers à modifier

- **`.claude/workflow-routing.yml`** (nouveau fichier, projet, committé) —
  cf. §"Routeur déclaratif" : un rôle par ligne, `{ provider: claude|codex,
  codex_effort? }`. Source de vérité unique pour "qui pilote quoi" et, pour
  les rôles Codex, "à quel effort" (§"Économie côté Codex") — remplace la
  duplication entre la table "Qui fait quoi dans le workflow" et la logique
  qu'`orchestrate.md` aurait sinon codée en dur.
- **`codex-handoff.sh`** — cf. §"Économie côté Codex", proposition 1 : lire
  `codex_effort` du rôle concerné dans `.claude/workflow-routing.yml` et
  ajouter `-c model_reasoning_effort=<niveau>` (syntaxe à confirmer contre la
  version Codex installée, cf. le piège de version cité) à la commande
  externe qu'il imprime.
- **`.claude/commands/loop/orchestrate.md`**
  - Phase 0, étape 1 : ajouter la lecture conditionnelle du frontmatter YAML
    de `handoff-codex.md` sibling (`phase`/`execute_status`/`review_status`,
    cf. §"Repli dans les deux sens" point 3) pour choisir la phase de reprise
    (4, 5-jugement ou 5-correctifs déjà tranchés) au lieu de sauter
    systématiquement en Phase 4 sur tout `plan.md`.
  - Fin de Phase 3 / début de Phase 4 : lire `.claude/workflow-routing.yml`
    pour le rôle `execute-green` ; si `codex` **et** `command -v codex`
    réussit, écrire le handoff (réutilise le template de `/handoff:codex`),
    imprimer la commande externe et s'arrêter ; sinon (rôle `claude`, fichier
    absent, ou Codex indisponible) enchaîner Phase 4 inline, comportement
    actuel inchangé.
  - Fin du passage `reviewer`/`verifier` en Phase 5 : même lecture pour le
    rôle `review-fixes` — handoff vers Codex pour écrire les correctifs,
    reprise sur Claude pour le re-run des dimensions affectées.
  - Documenter le flag d'opt-out (ex. `--inline-execute`) pour forcer les deux
    bascules sur Claude même si `.claude/workflow-routing.yml` dit `codex` et
    que Codex est disponible.
- **`AGENTS.md`** — ajouter l'instruction de rafraîchissement du checkpoint
  après chaque étape/couche terminée, avec le même contenu minimal que celui
  qu'`orchestrate.md` décrit pour Claude — y compris le frontmatter YAML
  (`execute_status`/`review_status`), pas seulement la prose. Ajouter aussi la
  table effort-par-type-de-tâche du §"Économie côté Codex" (relais complet
  uniquement — la bascule délibérée reste réglée par
  `.claude/workflow-routing.yml`, pas par `AGENTS.md`).
- **`.claude/commands/handoff/codex.md`** — courte note indiquant qu'il est
  désormais aussi invoqué automatiquement par `/loop:orchestrate` à la
  frontière PLAN→EXECUTE. **Changement fonctionnel du template, pas
  seulement une note** : ajouter le bloc frontmatter YAML
  (`phase`/`execute_status`/`review_status`/`token_profile`) en tête, cf.
  §"Repli dans les deux sens", point 3 — `Current phase` en prose reste
  inchangé pour la lecture humaine, le frontmatter est ce que Phase 0 parse.
- **`.codex/config.toml`** (nouveau fichier, projet, committé) — une fois le
  POC hooks validé (§"POC hooks") : bloc `[[hooks.PreToolUse]]` sur
  `apply_patch` pour `tdd-require-red.sh` + les quatre garde-fous non-TDD
  (§"Garde-fous non-TDD") : `no-any-type.sh`, `enforce-architecture.py`,
  `no-forbidden-icons.sh`, `english-comments.py`. Condition de la bascule
  EXECUTE-GREEN par défaut, pas une amélioration optionnelle — cf.
  §"Garde-fous non-TDD" pour la raison.
- **`.claude/agents/reviewer.md`** — dimension `ui` : ajouter un critère
  explicite "icônes interdites" (`09-icons.md` — Star, Stars, Sparkle,
  Sparkles, Rocket, RocketLaunch, Zap, Bolt, LightningBolt + glyphes emoji).
  Filet en attendant que `.codex/config.toml` porte `no-forbidden-icons.sh` ;
  reste utile après, pour la même raison que le bullet "backstop" déjà présent
  sur l'archi (le hook ne voit que le delta d'un `Edit`).
- **`docs/RATIONALE.md`** et **`docs/Claude_Workflows.md`** — courte mise à
  jour narrative pour refléter la bascule délibérée (ces fichiers sont déjà
  dans le périmètre de `docs/audits/workflow.md`, donc à garder cohérents).
- **`.claude/rules/11-token-budget.md`** — remplacer la table `## Model
  tiers` par la nouvelle répartition 5 `inherit` / 6 `sonnet` / 1 `haiku`
  (contenu exact ci-dessus).
- **`.claude/agents/test-writer.md`, `e2e-tester.md`, `github.md`,
  `designer.md`** — `model: inherit` → `model: sonnet`.
- **`.claude/agents/story-writer.md`** — `model: haiku` → `model: sonnet`.
- **`.gitignore`** — ajouter `.claude/.kit-health.jsonl`, même statut que
  `.claude/.hook-timings.log` déjà présent (§"Sonde kit-health").
- **`.claude/hooks/kit-attempts.py`** — `record()`/`clear()` ajoutent aussi
  une ligne à `.claude/.kit-health.jsonl` (§"Sonde kit-health").
- **Les hooks de refus** (`tdd-require-red.sh`, `no-any-type.sh`,
  `enforce-architecture.py`, `no-forbidden-icons.sh`, `english-comments.py`,
  `prevent-destructive-commands.sh`) — une ligne dans
  `.claude/.kit-health.jsonl` au moment où ils refusent réellement, pas à
  chaque invocation (§"Sonde kit-health").
- **`.claude/commands/loop/review.md`** — troisième émetteur du
  §"Sonde kit-health" ("la boucle REVIEW : une ligne par finding, avec son
  verdict"), non listé jusqu'ici. `reviewer`/`verifier` sont en lecture seule
  (pas d'accès `Write`) — l'écriture dans `.claude/.kit-health.jsonl` doit
  donc être ajoutée à l'étape du fil principal qui reçoit leurs findings et
  verdicts, décrite dans ce fichier, pas dans les agents eux-mêmes.
- **`.claude/hooks/kit-doctor.py`** — nouvelle fonction `check_kit_health()`
  + nouvelle catégorie `("health", [check_kit_health])` dans `CHECKS`
  (`kit-doctor.py:1034`) ; trancher d'abord si les sévérités existantes
  (`OK`/`DIVERGENCE`/`MISSING`, `kit-doctor.py:35`) portent un résumé ou s'il
  faut un style de `Finding` informatif séparé (§"Sonde kit-health").

Aucun changement dans `src/`/`shared/` : uniquement des commandes, agents,
`AGENTS.md` et de la doc — hors périmètre TDD (`05-testing.md` ne couvre que
`src/` et `shared/`), donc pas de cycle RED/GREEN à appliquer ici.

## Vérification (le jour de l'implémentation)

- Relecture croisée : la nouvelle branche de Phase 4 ne doit pas contredire
  la règle existante "Do not delegate" de Phase 4 (qui parle des sous-agents
  Claude, pas de Codex en process séparé — à expliciter dans le texte pour
  éviter l'ambiguïté).
- Vérifier à la main que `command -v codex` est bien le même test que celui
  déjà utilisé dans `codex-handoff.sh:7`.
- `.claude/workflow-routing.yml` absent → Phase 0/4/5 se comportent exactement
  comme avant ce plan (tout Claude) ; présent avec `execute-green.provider:
  codex` ou `review-fixes.provider: codex` mais Codex absent du `PATH` → même
  repli, pas d'erreur.
- `codex-handoff.sh` : sur un rôle `codex_effort: low`, la commande imprimée
  porte bien `-c model_reasoning_effort=low` (ou l'équivalent confirmé) — et
  sur `.claude/workflow-routing.yml` absent, la commande reste identique à
  aujourd'hui (pas de flag ajouté par erreur).
- Relire un `handoff-codex.md` réel existant (s'il y en a un dans
  `docs/work/`) pour confirmer que le frontmatter YAML
  (`phase`/`execute_status`/`review_status`) a un format stable à parser en
  Phase 0 — et vérifier que Phase 0 route bien vers les 3 branches distinctes
  (reprise Phase 4 / Phase 5-jugement / Phase 5-correctifs déjà tranchés) sur
  un handoff réel, pas seulement sur l'exemple du template.
- Si le POC hooks (§"POC hooks") passe : `.codex/config.toml` doit refuser un
  `apply_patch` de test sur chacun des cinq cas (RED non prouvé, `any`,
  import cross-feature, icône interdite, commentaire non anglais) — un seul
  suffit à valider le mécanisme, les cinq confirment qu'aucun n'a été oublié
  dans le portage.
- `reviewer.md` : sur une diff de test contenant une icône interdite, vérifier
  que la dimension `ui` la remonte — avant et indépendamment du portage des
  hooks, puisque c'est un filet permanent, pas seulement transitoire.
- `python3 .claude/hooks/kit-doctor.py` doit rapporter `agent-models: OK`
  avec le décompte 5 `inherit` / 6 `sonnet` / 1 `haiku` après le volet tiers.
- **Mesurer l'économie Claude, pas la deviner** : le tableau coût/bénéfice
  ci-dessus (§"Où pousser plus loin") note "Élevée"/"Moyenne"/"Faible" sans
  aucune donnée derrière — `docs/work/` est vide à ce jour et
  `docs/measuring-the-loop.md` prévient explicitement que ce genre de pari a un
  mauvais historique dans ce kit (trois hypothèses posées dans un audit passé,
  trois fausses). Avant de considérer la bascule EXECUTE-GREEN/REVIEW-fix comme
  acquise, comparer sur au moins une feature réelle **avant** la bascule et une
  **après** : le nombre d'appels `Edit`/`Write` que Claude émet lui-même en
  inline (Phase 4 GREEN, correction Phase 5). Méthode : si la sonde
  kit-health (§"Sonde kit-health") existe déjà, une requête sur
  `.claude/.kit-health.jsonl` ; sinon, une lecture du transcript per-tour, la
  méthode déjà décrite dans `docs/measuring-the-loop.md` ("Everything else:
  the session transcript is timestamped, per turn and per agent"). Si ce
  compte ne baisse pas nettement après la bascule, le coût de l'aller-retour
  (écrire/lire le handoff, Codex qui relit `AGENTS.md` + `CLAUDE.md` +
  l'artefact) a probablement mangé le gain annoncé — revoir le tableau du
  §"Où pousser plus loin" avec ce chiffre plutôt qu'avec l'estimation
  qualitative actuelle.
- Sur la feature suivante lancée en profil `economy`, noter les deux chiffres
  qui décident si le volet tiers tient : le nombre d'allers-retours RED de
  `test-writer`, et le nombre de findings remontés par `story-critic` sur les
  stories produites par `story-writer` — même remarque : sonde kit-health si
  elle existe, comptage manuel sinon.
- `.claude/.kit-health.jsonl` : après quelques features, `python3
  .claude/hooks/kit-doctor.py` doit rapporter une entrée `health` non vide —
  au minimum un gate et un hook représentés, sinon les émetteurs
  (`kit-attempts.py`, les hooks de refus, la boucle REVIEW) n'écrivent pas
  réellement.
- Pas de test automatisé applicable (fichiers de commande/doc) : vérification
  par lecture et cohérence croisée entre les fichiers listés.
