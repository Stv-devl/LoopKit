# Plan de refonte LoopKit

Version du 25/10/2026, révisée le même jour après un audit du plan :
`plan-critic` à l'aveugle, puis `verifier` qui a réfuté les constats un par un.
Fusion de l'audit tokens (arbitré en trois tours) et du journal d'erreurs relevé
sur EcoCrew (`install --react-ts --fastapi --no-ci`). Chaque affirmation a été
vérifiée contre le dépôt ; les points non vérifiables d'ici sont marqués **à
vérifier**.

Branche : `audit/slim`, un commit par étape (section « Ordre de mise en œuvre »).

---

## Partie 1 — Coût en tokens

### Constat

- Instructions permanentes : `CLAUDE.md` + rules = 25,5 Ko, environ 7k tokens,
  chargés par la session et par chaque sous-agent.
- **Le cache ne sert presque pas aux sous-agents** (mesuré sur EcoCrew, 1 406
  lancements). Ils écrivent leur cache avec une durée de vie de 5 min. Au
  premier tour, chaque lancement écrit 21 à 35k tokens. Même relancé dans les
  5 min, le même agent n'en relit qu'environ 6k ; les lancements en parallèle
  (389) n'en relisent presque rien. Le reste (définition de l'agent,
  `CLAUDE.md` et rules, tâche) est réécrit à chaque fois. Cause probable, **non
  vérifiée** : un élément propre à chaque lancement placé avant les rules par le
  harnais, hors de portée du kit. Conséquence : un token retiré d'une rule ou
  d'une définition d'agent est économisé plein tarif à chaque lancement.
- **La session principale coûte plus que tous les sous-agents réunis** :
  68 % de $2 256 sur l'historique EcoCrew (`docs/measurements/token-baseline.md`,
  35 sessions, 337 tours médians par session). L'essentiel est la relecture en
  cache d'un contexte qui grossit à chaque tour (5 milliards de tokens lus). Par
  phase : execute 36 %, review 35 %, plan 13 %, research 7 %, ship 6 %,
  interface 4 %. Levier non traité par ce plan : la longueur des sessions (une
  session enchaîne plusieurs features). À décider après la mesure de l'étape 0.
- **Efficacité mesurée des agents** (journal de santé d'EcoCrew) : `reviewer`
  239 findings confirmés ; `plan-critic` bloque 66 % des plans (118 sur 179) ;
  `verifier` a réfuté 27 findings ; `test-writer` 7 % de relances, aucun
  blocage ; `e2e-tester` 3 bugs confirmés en 35 lancements. Aucun agent du kit
  n'est une perte de temps : on allège, on ne supprime pas. Le seul gaspillage
  mesuré est le travail fait sans agent attitré (`general-purpose`, 1.8).
- Répartition mesurée du coût des sous-agents (équivalent API, $722) :
  `reviewer` 40 %, `general-purpose` 22 % (travail sans agent attitré, voir
  1.8), `plan-critic` 16 %, `test-writer` 7 %, le reste ≤ 3 % chacun. Remplacer
  Sonnet par Opus low ne rapporte rien : la sortie ne pèse qu'environ 5 % des
  tokens, et Opus paie deux fois plus cher les 21 à 35k écrits au départ.
- Skills et research-cache : payés seulement quand ils sont lus.
- Codex : aucun modèle imposé ; le relais part sur deux causes sans rapport
  (quota ou reprises épuisés, contexte saturé via `.codex-ready`) ; le checkpoint
  laisse Codex décider la suite.
- Le chiffre de 156k par feature était une estimation : il faut une mesure.

### Objectif

Mesurer, puis réduire nettement les tokens neufs par feature, sans retirer
aucune vérification indépendante ni aucun garde-fou contre l'hallucination.

### 1.0 Mesure : `kit-measure.py`

Part de `docs/measuring-the-loop.md` (où sont les chiffres, quelles hypothèses
ont déjà été démenties) et le complète, sans doubler `hook-timings-report.sh`.
Base de départ : les trois prototypes de `docs/measurements/prototypes/`, qui ont
produit les chiffres du Constat : `agg.py` (compteurs par agent et par modèle),
`first.py` (cache au premier tour), `cost.py` (coût équivalent API). Ils lisent
`<transcript>/subagents/*.meta.json` (`agentType`) et le `usage` des messages
assistant, dédoublonnés par `message.id`.
Emplacement : `.claude/hooks/kit-measure.py`, avec un test sur un transcript de
fixture dont les compteurs attendus sont écrits à la main.

Lit les transcripts de la session et de ses sous-agents. Par agent et par phase :

- quatre compteurs séparés : entrée neuve, écriture en cache, lecture en cache,
  sortie ;
- un coût pondéré aux prix de l'API (lecture 0,1×, écriture 1,25× ou 2×), donné
  à titre indicatif : le décompte du cache dans un abonnement n'est pas public.

**Attribution par phase** : les transcripts ne portent pas de marqueur de
phase. La découpe se fait sur les écritures de l'orchestrateur dans
`docs/work/<slug>/` (`research.md`, `design.md`, `plan.md`, mises à jour du
handoff), horodatées dans le transcript.

Vérifie aussi : `effort` passé à l'appel réellement appliqué (le transcript
l'enregistre : `"effort":"medium"` dans les messages, vérifié sur EcoCrew) ; héritage ou non de l'effort de session par
un agent sans effort en frontmatter ; taux de lecture en cache des lancements
successifs d'un même agent.

**Feature de référence** : une story EcoCrew figée (même dépôt, même commit de
départ, même profil), nommée dans le fichier de sortie. Toutes les mesures la
rejouent ; sans elle, un gain peut venir d'une feature plus petite.

**Points de mesure** : référence (étape 0), puis après les étapes 7, 8, 9 et 10,
chacune comparée à la précédente. Une seule mesure finale ne dit pas lequel des
changements a rapporté.

Sortie (décidé) : `docs/measurements/token-baseline.md`, versionné. Pas sous
`docs/audits/`, ignoré par git (`.gitignore:101`).

### 1.1 Modèles et effort

| Rôle | Agents | Réglage |
| --- | --- | --- |
| Validation | reviewer, verifier, plan-critic, story-critic, security-auditor | `model: inherit` conservé, pas d'`effort` en frontmatter ; effort passé à l'appel : medium en economy/standard, high en critical |
| Tests | test-writer | sonnet + high |
| Production | designer, story-writer, doc-researcher, e2e-tester, github | sonnet + medium |
| Exploration | explorer | haiku |
| Session principale | | Opus medium, high en critical |

- `model: inherit` reste : le retirer casse `test-workflow-contracts.sh:19` et
  le check `agent-models`.
- Le tableau de `11-token-budget.md` garde sa forme lisible par `kit-doctor.py`
  (`check_agent_models`, l.543-552) : 1re colonne `` `tier` ``, agents en
  **dernière** colonne. L'effort va dans une colonne placée avant celle des
  agents.
- Session principale : aujourd'hui rien ne la règle (`workflow.py:146-157`
  transmet `sys.argv` tel quel, `workflow.sh` et `.claude/settings*.json` ne
  fixent ni modèle ni effort). `workflow.py` passe `--model opus` et
  `--effort medium` (`high` en critical) : les deux options existent dans
  `claude --help`. Consigné dans `settled.md`.

Si `effort` n'existe pas à l'appel (Claude Code plus ancien), l'agent tourne à
son effort par défaut : rien ne casse, mais critical perd son effort high. À
écrire dans `11-token-budget.md` et son guide. Tableau de `11-token-budget.md`
mis à jour dans le même commit.

### 1.2 Codex et seuil de 97 %

- `codex_model` à côté de `codex_effort` dans `workflow-routing.yml`, `-m` dans
  `codex-handoff.sh`. `gpt-5.6-terra` en low pour `execute-green` et
  `review-fixes` (identifiant lu dans `~/.codex/models_cache.json`, codex-cli
  0.154.0), consigné dans `settled.md`.
- Relais Codex réservé au quota et aux reprises épuisés, borné à une étape :
  finir l'étape atomique, passer ses gates, s'arrêter. **La règle E16 s'y
  applique** : aujourd'hui `workflow.py:275-282` relaie sans regarder l'étape.
  Si l'étape en cours n'a pas de gate qui tourne sans réseau (backend, e2e),
  `workflow.py` écrit le checkpoint et s'arrête au lieu de lancer Codex.
- Contexte saturé : `workflow.py` ne lance plus Codex, il relance
  `claude "/loop:orchestrate docs/work/<slug>/handoff.md"`. **La phase 0 ne sait
  pas encore le faire** : elle ne reprend que depuis un `plan.md` qui a un
  handoff voisin, et ses trois branches ne couvrent qu'execute et review
  (`orchestrate.md:99-109`). À ajouter :
  - `handoff.md` reconnu comme artefact d'entrée de la phase 0 ;
  - une branche par phase (research, interface, plan, execute, review), lue
    dans un frontmatter `phase:` obligatoire ;
  - `write_handoff_checkpoint` (`workflow.py:105-127`) écrit ce frontmatter.
    Il ne garde plus un handoff existant tel quel (`if handoff.exists():
    return`, l.115) : il met à jour ses champs ;
  - le compteur de relances vit dans ce même frontmatter (`restarts: N`, décidé).
    Plafond : 2 relances par feature, puis arrêt avec « phase trop grosse, à
    redécouper dans le plan » ;
  - un cas par branche dans `test-workflow-contracts.sh`.
- Renommage avec transition : `.codex-ready` → `.restart-ready`,
  `handoff-codex.md` → `handoff.md`. `install.sh` ignore anciens et nouveaux
  noms ; la phase 0 accepte encore `handoff-codex.md` pendant une version.
- Fichiers qui changent ensemble :
  - `.codex-ready` (8) : `workflow.py`, `install.sh`, `.gitignore`,
    `.claude/rules/11-token-budget.md`, `.claude/guides/11-token-budget.md`,
    `token-statusline.py`, `kit-doctor.py`, `orchestrate.md` ;
  - `handoff-codex.md`, en plus : `.claude/commands/handoff/codex.md` (c'est
    lui qui écrit le fichier, l.24 et 27), `AGENTS.md`,
    `docs/Claude_Workflows.md`, `docs/RATIONALE.md`, et la copie du handoff
    ajoutée par D13 à l'étape 3.
  - Contrôle de fin d'étape : `rg -l "codex-ready|handoff-codex"` ne retourne
    que les lignes de transition.
- Les 12 renvois morts vers `docs/codex-claude-split-plan.md` (le fichier
  n'existe plus) : remplacer chacun par un renvoi vers le lecteur du schéma
  `.kit-health.jsonl`, la fonction health de `kit-doctor.py` (l.1041), au lieu
  de les supprimer à sec. Cinq sont des commentaires de hooks (`hook-lib.sh`,
  `kit-attempts.py`, `kit-doctor.py`, `enforce-architecture.py`,
  `english-comments.py`).
- Voir aussi 2.E (sandbox sans sockets, condition de course).

### 1.3 Instructions permanentes

- `CLAUDE.md` : retirer la méta-explication du Rules Index. Les lignes `@` et
  les marqueurs de remplissage restent (`rules-loaded`, `fill-markers`).
- La section « Reading a path » **reste**, compactée : c'est un piège au sens
  même de `CLAUDE.md` (« a trap stays in the rule »). Elle empêche de prendre un
  `docs/work/<slug>/` absent pour un lien cassé, ou d'inventer un chemin sous
  `.claude/`. Trois renvois la citent (`kit-doctor.py:699`,
  `commands/kit/doctor.md:129`, `.gitignore:93`) : à mettre à jour si son titre
  change.
- Rules : couper aussi, selon les trois sorties de `CLAUDE.md` ; budgets baissés
  dans le même commit, `test-rules-floor.sh` au vert.

### 1.4 Commandes et agents

- `reviewer.md` : 25 → environ 10 Ko, une checklist par dimension, chaque
  reviewer ne lit que celles de son lot. Le plafond de 2 reviewers en economy
  existe déjà (`review.md:91`), inchangé.
- `orchestrate.md` : 27 → environ 8 Ko ; `ship.md` : 16 → environ 6 Ko. Les
  justifications partent dans `.claude/guides/`.
- Les phrases que `test-workflow-contracts.sh` vérifie à l'octet près restent
  intactes : l.27-28 et 55 pour `orchestrate.md`, l.78-80 pour `reviewer.md`.
- Test-writer : un seul lancement par feature, continué avec `SendMessage` à
  chaque couche. RED puis GREEN couche par couche inchangé ; toujours interdit de
  lire le module testé.
  - Risque accepté et à surveiller : le contexte gardé d'une couche à l'autre
    transporte les contrats déduits des couches précédentes, ce que le
    découpage par couche évitait en partie (`orchestrate.md:353`).
  - Le changement est mesuré à part (point de mesure après l'étape 9) ; si le
    cache ne rapporte rien, on revient à un lancement par couche.
  - Textes à mettre à jour ensemble : section RED d'`orchestrate.md`,
    `CLAUDE.md:129` (« one `test-writer` per test-first layer »),
    `.claude/agents/test-writer.md:3`, et les contrats de
    `test-workflow-contracts.sh` qui les citent.

### 1.5 Agent `github` : conservé

Principe retenu pour toute la partie 1 : **un agent efficace est allégé, jamais
supprimé ; seul un agent qui fait perdre du temps est retiré.** Mesuré sur
EcoCrew, `github` est efficace : 105 commits et merges sans échec, $9 au total
($0,09 par lancement), et il isole la convention git et la validation avant
push. Le supprimer ne rapportait rien de mesurable. Il reste ; seuls deux points
le touchent :

- C11 (commits d'une ligne, pas de trailer, le rappel d'attribution du harness
  ne s'applique pas) s'écrit dans `github.md`, qui porte déjà la convention.
- D13 (vérification avant `git worktree remove`) s'écrit dans son bloc de
  nettoyage (`github.md:133`), là où la commande s'exécute.

### 1.6 Skills et cache

- Supprimer `snapshot-tests` (aucun renvoi).
- Réduire aux conventions propres au projet, sans supprimer : patterns
  `react-query`, `zustand`, `context`, `guards`, `forms`, `local-state`, `msw` ;
  template `feature` (après F19, qui le modifie à l'étape 4).
- `a11y` : garder les règles d'interaction, retirer les exemples génériques.
- Cache : `tanstack-query-v5`, `zustand-v5`, `testing-tooling` réduits aux pièges
  propres à la version ; `settled.md` sans méta-explication ; `motion` et `gsap`
  inchangés.
- Addons FastAPI et Supabase : exemples d'API des SDK vers le cache,
  l'architecture reste.

### 1.7 Context7

- **Optionnel, priorité basse** : `doc-researcher` ne pèse qu'environ 0,3 % du
  coût sur EcoCrew (7 lancements, environ $2). Ajouté au seul `tools:` de
  `doc-researcher`, jamais une dépendance : sans le serveur, l'agent suit
  l'ordre ci-dessous sans cette étape.
- L'installation du serveur MCP revient à l'utilisateur (`install.sh` ne le
  câble pas, Context7 n'est pas installé sur la machine de référence). Le nom
  des outils est relevé avec `/mcp` au moment de l'installation, pas supposé.
- Ordre : `settled.md` et le cache → savoir du modèle pour les API stables
  seulement → un appel Context7 ciblé → WebFetch en dernier recours.
- Partage inchangé : l'agent écrit son fichier de sujet et renvoie « Promote to
  the ledger » ; seul le thread principal écrit dans `settled.md`.

### 1.8 Travail sans agent attitré

Sur EcoCrew, 88 lancements de `general-purpose` (22 % du coût), tous du travail
que le kit ne confie à aucun agent. Faute d'agent, ils héritent d'Opus, sans
effort ni limite.

| Usage | Lancements | Coût | Modification |
| --- | --- | --- | --- |
| Implémentation déléguée (EXECUTE, relais Codex) | 10 | $102, 117 tours chacun | Nouvel agent `implementer` |
| Corrections après review ou e2e | 7 | $28 | `implementer` |
| Tests après le code (hooks, UI, API) | 36 | $45 | `test-writer`, mode « après le code » |
| Réparation de specs e2e | 7 | $23 | `e2e-tester` |
| `/database:migration` (`context: fork`) | 28 | $19 | `model:` explicite dans la commande, Opus conservé |

- **`implementer`** : sonnet + medium, le niveau « production bornée depuis une
  entrée validée ».
  - Il reçoit un lot borné : une couche GREEN, ou un lot de findings à corriger.
    Il ne touche jamais aux tests : le hook de gel le borne déjà.
  - Il remplace l'implémentation inline quand la session la délègue, et sert de
    repli quand Codex est absent.
  - Quand déléguer (décidé) : GREEN reste inline par défaut. La session
    délègue quand son contexte dépasse 70 %, et toujours pour un lot de
    findings à corriger (phase 5). Le seuil de 70 % est un nouveau marqueur
    `.token-delegate` écrit par `token-statusline.py`, à côté des seuils 90, 95
    et 97, et synchronisé avec `11-token-budget.md` comme eux. Cité dans
    `orchestrate.md` (GREEN, phase 5). La valeur est revue après mesure.
  - Textes à mettre à jour ensemble : la liste des agents de `CLAUDE.md`, le
    tableau de `11-token-budget.md` (ligne `sonnet`), `kit-doctor.py`
    (`agent-models`, `agent-refs`) et `test-workflow-contracts.sh`.
- **`test-writer` après le code** : un mode nommé dans le prompt de lancement.
  Il peut lire l'implémentation, il n'y a ni RED ni gel, et l'attendu vient
  toujours d'une source que le code ne peut pas atteindre (`05-testing.md`).
  La description de l'agent et `orchestrate.md` (couches test-after) le citent.
- **`e2e-tester`** : sa description couvre aussi la réparation et la migration
  de specs existantes.
- **`/database:migration`** : `model: opus` dans le frontmatter. Avec
  `context: fork`, ce champ règle le modèle du sous-agent forké, et il accepte
  les alias de `/model` (doc des skills de Claude Code). Une migration relève des changements de données
  destructifs, donc du profil critical : on n'économise pas dessus.
- Mesure : `general-purpose` doit tomber près de zéro sur la feature de
  référence. Ce qui reste est un nouveau trou à attribuer.

### 1.9 Une session par feature : `/clear` après le ship

La session principale pèse 68 % du coût, et une session qui enchaîne les
features relit l'historique des précédentes à chaque tour (mesuré sur EcoCrew :
277k tokens par tour pendant la 1re feature, 456k à partir de la 4e ; jusqu'à 15
features dans une même session). Cause : le travail à distance en Remote
Control, qui garde une seule session ouverte.

Ni le modèle ni un hook ne peuvent vider le contexte : `/clear` est une commande
de l'utilisateur, et elle fonctionne depuis le mobile et le web (doc Remote
Control). Un hook peut seulement réagir à un `/clear`. D'où :

- **Fin de `/loop:ship`** : « Feature livrée. Tape `/clear` pour passer à la
  suivante. » au lieu de nommer seulement la suivante.
- **Hook `SessionStart`, déclenché seulement sur `clear`** (`source: "clear"`) :
  lit le board et `docs/work/`, et injecte la feature suivante avec sa commande
  (`/loop:orchestrate <artefact>`) en `additionalContext`. L'utilisateur tape
  `/clear` puis `go`. `initialUserMessage`, qui lancerait le tour seul, ne
  marche qu'en mode `-p`. Fixtures : board avec une feature suivante, board
  vide, pas de board.
- **`.claude/guides/10-worktrees.md`**, section « travailler à distance » :
  `/clear` entre deux features dans une même session RC, et le mode serveur
  `claude remote-control --spawn worktree` pour lancer depuis le téléphone une
  session et un worktree par feature, en parallèle.
- Écarté : relancer la feature suivante dans un `claude -p` en arrière-plan.
  Invisible depuis le téléphone, et personne pour valider interface et plan.
- Mesure : le contexte relu par tour reste stable d'une feature à l'autre.

---

## Partie 2 — Défauts terrain (EcoCrew)

Verdict par point : **Bug** (le kit est faux), **Trou** (le kit ne dit rien),
**Local** (écart du projet, mais le kit doit le détecter), **Couvert** (le kit
le dit déjà), **Refusé**.

### A. Hooks TDD

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 1 | Bug | `addons/fastapi/hooks/tdd-prove-red-py.py`, `imported_symbols` (l.70) : la clause capturée par `[^\n]+` garde le commentaire, `f  # isort: skip` n'est pas un identifiant. Même défaut dans la recherche d'alias du parent (l.82). | Retirer `#…` de chaque ligne avant d'aplatir. **Pas de fixture `test-hooks.sh`** : il n'exécute que `.claude/hooks/` (l.120) et le hook lance pytest. Un test Python direct importe le module et vérifie `imported_symbols` sur `f  # isort: skip` et `(a,  # c\n b)`, ensembles attendus écrits à la main. |
| 2 | Bug | `tdd-prove-red.sh` ne reconnaît que `import { … } from` et `import * as` (l.133, 146). | Reconnaître `const { a, b } = await import('…x.mapper')`, `(await import('…')).a` et `vi.importActual('…')` : c'est la forme normale de Vitest pour charger un module après `vi.mock`, on ne peut pas l'interdire. `vi.importMock` n'est pas couvert (il ne charge pas le module testé). Fixtures. |
| 3 | Trou partiel | `tdd-require-red.sh` exige que tout nouvel export figure dans le marqueur RED : c'est voulu. Le refus propose déjà d'ajouter un cas (l.207). | Pas une ligne de rule (budget). Le texte de refus ajoute la seule option manquante : garder l'export non exporté. |
| 4 | Bug | `test-writer` a `Write` mais pas `Edit` ; un fichier gelé n'accepte qu'une insertion par `Edit`. Agent bloqué. | Ajouter `Edit` à `tools:`. Le hook de gel borne déjà `Edit` à l'insertion pure sur un fichier de test. Pour un fichier d'implémentation, la limite est **vérifiée par un hook, pas confiée au prompt** : l'entrée d'un hook `PreToolUse` porte `agent_type` quand l'appel vient d'un sous-agent (vérifié dans la doc des hooks de Claude Code). Le hook refuse `Write`/`Edit` du `test-writer` hors d'un fichier de test. Fixtures avec et sans `agent_type`. |
| 5 | Couvert | `tdd-freeze-tests.sh:235` : l'ancre ne doit pas contenir `expect(`. Le refus le dit déjà et propose une ancre valable : « the closing '});' of the previous one » (l.357). | Rien sur l'ancre. Les 298 lignes d'historique de `.claude/.tdd-unfrozen` sur EcoCrew ne montrent aucun dégel dû à `expect(`. Les problèmes d'ancre relevés sont autres : ancre de fin de fichier non unique, espace perdu dans la ligne d'ancre. En revanche, `tdd-freeze-tests.sh` n'écrit aucun refus dans `.kit-health.jsonl` (absent des sources sur EcoCrew) : il l'écrit désormais, comme `tdd-require-red`. |
| 6 | Trou | Un caractère invisible (U+00A0, U+202F, BOM, espace de largeur nulle) dans la charge Write/Edit arrive brut ; plusieurs dégels dans `.tdd-unfrozen` en viennent. U+202F est celui que produit `Intl` en fr-FR, la langue des messages. | Dans `tdd-freeze-tests.sh` (décidé : il lit déjà chaque charge Write/Edit sur un fichier de test, pas de hook de plus) : sur un fichier de test, refuser un caractère invisible brut et dire d'écrire l'échappement doublé (`\\u00a0`, `\\u202f`) dans la charge. Fixture par caractère, U+202F nommé. Une ligne dans le prompt du test-writer. Pas de ligne de rule : le refus suffit. |

### B. Gates de `/loop:ship`

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 7 | Bug | `pip-audit` lancé par `uvx` audite son propre environnement jetable : faux vert. Le README (`addons/fastapi/README.md:93`) et `07-backend.md:37` citent `uv pip audit`, qui n'existe pas (vérifié avec uv 0.12.23 : `unrecognized subcommand`). La commande réelle est `uv audit`, au niveau du projet, qui lit `uv.lock`. | Gate bloquant : `uv audit --frozen --no-dev` (pas d'environnement jetable, pas de fichier temporaire). Même politique que B8 : `uv audit --frozen --only-dev` est signalé à part, sans bloquer. Pas de version minimale à suivre : le gate lance `uv audit` et, si uv répond `unrecognized subcommand`, passe au repli. Repli : `uv export --frozen --no-hashes --no-emit-project --no-dev` puis `uvx pip-audit --disable-pip --no-deps -r`. À corriger dans `addons/fastapi/rules/07-backend.md`, `README.md`, `commands/backend/deps-audit.md`, `security.md`, `/loop:ship` et `templates/ci.md`. |
| 8 | Bug | `ship.md:40` lance `pnpm audit --audit-level=high` (dev inclus), `00-project.md:18` liste `pnpm audit`, le script du projet fait `--prod`. Trois sources. | Une seule : le gate lance `pnpm run audit`. `pnpm audit` est une commande intégrée de pnpm et n'appelle jamais un script `audit`. Le template (`tooling-config.md`, qui n'en définit pas aujourd'hui) le définit `pnpm audit --prod --audit-level=high`. Ajouter `Bash(pnpm run *)` à `.claude/settings.json`, exigé par `check_gate_allowlist` (`kit-doctor.py:344-350`). Copies à aligner : `ship.md`, `00-project.md`, `templates/github/ci.yml:130`, `templates/ci.md`, `agents/security-auditor.md:132`, `commands/kit/doctor.md:70`. `commands/bmad/flow.md` est hors périmètre et reste une source à reprendre plus tard. Les CVE de dev sont signalées à part, sans bloquer. `/kit:doctor` compare le script et la commande du gate. |
| 9 | Trou | Le kit ne lance pas d'e2e par défaut (marqueur dans `ship.md:53`) ; EcoCrew les a enchaînés après vitest + coverage, d'où l'intermittence. | Le commentaire du marqueur et la skill `e2e-playwright` disent : e2e dans une commande séparée, après les gates unitaires, jamais dans le même lot parallèle. |
| 10 | Refusé en l'état | Une erreur non gérée fait sortir Vitest en code 1 même si les tests passent : le gate a raison, ce n'est pas un faux rouge. | `patterns/tests.md` : stubber dans le setup jsdom ce que jsdom n'implémente pas (`document.elementFromPoint`, `Range.getClientRects`) pour les éditeurs riches. Jamais « ignorer le code de sortie ». |

### C. Agents et conventions

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 11 | Trou | Le hook refuse déjà les trailers et son texte dit que la convention l'emporte sur toute instruction de base. Le rappel système de Claude Code demande le contraire. | Trancher pour la convention du kit (commits d'une ligne, pas de trailer). L'écrire dans `github.md` (1.5), avec la mention explicite que le rappel d'attribution du harness ne s'applique pas. |
| 12 | Bug | `03-conventions.md` exige un commentaire d'une ligne pour justifier une exception de mémoïsation ; `english-comments.py` n'autorise que la JSDoc. | Le hook accepte une forme unique et reconnaissable juste au-dessus d'un `useMemo`/`useCallback`/`memo` : `// memo: <raison>`. La rule nomme cette forme. Fixture. |
| 13 | Bug | `english-comments` est le hook qui refuse le plus (181 refus sur EcoCrew). Une fois les répétitions de fixtures retirées, **aucun vrai commentaire français** n'a été écrit. Environ 110 refus visent des JSDoc anglaises qui citent le texte de l'interface en français (« Mesures non classées », « Confirmer l'unité ») ou un terme métier (Métré, Calques). C'est légitime : la langue de l'interface est le français (`03-conventions.md`). Ensuite, 18 refus visent des consignes d'insertion laissées dans le code (`// IMPORT: add …`, `// Append at the END …`). Enfin, le journal écrit toujours `"file": ""` (`english-comments.py:73`). | Le détecteur de français ignore ce qui est cité : `« … »`, guillemets droits et backticks. Fixtures : une JSDoc anglaise citant « Mesures non classées » passe, « Vérifie la valeur » est refusé. Le texte de refus des consignes d'insertion dit d'appliquer la consigne au lieu de l'écrire. Le journal reçoit le chemin du fichier. Pas de ligne dans `CLAUDE.md` : le modèle écrit déjà en anglais, l'erreur vient du hook. |

### D. Worktrees

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 13 | Local + Trou | Dans le kit, `docs/work/<slug>/` est versionné (seul `handoff-codex.md` est ignoré, `.gitignore:106`). EcoCrew l'ignorait : `git worktree remove` a supprimé plan, design et recherche. | `/kit:doctor` : nouveau check, `docs/work/` et les parties livrées de `.claude/` ne doivent pas être ignorées ; cas dans `test-kit-doctor.sh`. Avant `git worktree remove`, vérifier que `docs/work/<slug>/` est suivi et commité (`git status --ignored --porcelain docs/work/<slug>`) ; sinon le copier dans l'arbre principal et vérifier la copie. Le handoff ignoré est copié aussi s'il n'a pas été consommé. **Emplacement** : là où la commande s'exécute, c'est-à-dire le nettoyage de `github.md:133` (`ship.md:182` ne couvre que le worktree d'une autre piste). L'agent est conservé (1.5) : la vérification y reste. |
| 14 | Local + Trou | Le kit n'ignore pas `.claude/` ; EcoCrew oui. Les hooks tournent via `$CLAUDE_PROJECT_DIR`, mais `kit-attempts.py` doit être appelé par chemin absolu, et une session isolée ne peut pas écrire à travers. | Même check `/kit:doctor` que 13. `.claude/guides/10-worktrees.md` : section « Ce qui vit dans l'arbre principal » (hooks, `kit-attempts.py`, marqueurs). |
| 15 | Trou | Addon FastAPI : la base de test par worktree devient périmée si un rebase change la chaîne Alembic sous un id inchangé. | `addons/fastapi/guides/` : supprimer `<db>_test_<worktree>` après un rebase qui touche les migrations, `conftest` la recrée. |
| — | Trou | `prettier --write` sur un dossier entier : 99 fichiers reformatés, 12 conflits de rebase. | `10-worktrees.md` : formater les seuls fichiers modifiés (le hook `format-on-save.sh` le fait déjà). `prevent-destructive-commands.sh` : demander confirmation sur un formateur en écriture appliqué à un dossier. Fixture. |

### E. Handoff Codex

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 16 | Trou | Le sandbox `workspace-write` de Codex n'a pas de sockets : ni pytest sur PostgreSQL, ni Playwright. | `workflow-routing.yml`, `/handoff:codex` **et le relais quota de `workflow.py`** (1.2) : Codex ne reçoit que des étapes dont les gates tournent sans réseau (couches front, tests unitaires). Une étape backend ou e2e reste sur Claude, ou s'arrête sur un checkpoint quand Claude n'a plus de quota. |
| 17 | Bug | `Write` du handoff et lancement de `codex-handoff.sh` dans le même message : le Write a échoué, le script est parti avec l'ancien fichier. | `/handoff:codex` et `orchestrate.md` : lancer le script seulement après le résultat du Write. `codex-handoff.sh` refuse un handoff plus ancien que le dernier commit ou que le plan. |

### F. Install et init

| # | Verdict | Constat vérifié | Modification |
| --- | --- | --- | --- |
| 18 | Bug | `wire_fastapi` câble les hooks et la rule, pas les autorisations des gates backend ; `install.sh` sait déjà fusionner `permissions.allow`. | Fragment d'autorisations de l'addon (`uv run pytest`, `ruff`, `mypy`, l'audit de 7) fusionné par `wire_fastapi`. Cas ajouté à `test-install.sh`. |
| 19 | Bug | `templates/feature.md`, `templates/fixtures.md`, `patterns/react-query.md` codent `@/lib/client` en dur ; `/kit:init` ne les réécrit pas. `tooling-config.md:324` exclut aussi `src/lib/client.ts` de la couverture en dur : un client placé dans `src/lib/api.ts` tombe sous `src/lib/**` et pèse sur les seuils. | Les templates citent le module déclaré dans `01-stack.md` au lieu d'un chemin en dur. `/kit:init` réécrit l'exclusion de couverture de `tooling-config.md` vers ce module, et vérifie qu'aucun `@/lib/client` ne reste quand le client déclaré est ailleurs. La liste des trois exclusions de `05-testing.md` suit le même nom. |

---

## Ordre de mise en œuvre

Les corrections de bugs passent avant l'allègement : elles bloquent un projet
réel aujourd'hui. Chaque correction de hook arrive avec sa fixture ou son test.

**À chaque commit**, pas seulement à la fin : `/kit:doctor`, `test-hooks.sh`,
`test-install.sh`, `test-kit-doctor.sh`, `test-rules-floor.sh`,
`test-attempts.sh`, `test-measure.sh`, `test-workflow-contracts.sh` au vert.

0. `kit-measure.py` avec son test, et mesure de référence sur la feature figée
   (1.0).
1. Hooks TDD : A1, A2, A4, A6, puis A3 (texte de refus). A5 seulement si le
   refus reçu sur EcoCrew diffère de `tdd-freeze-tests.sh:357`.
2. Gates : B7, B8, B9, B10.
3. Worktrees : D13 (perte de données, priorité, écrit dans le nettoyage de
   `github.md`), D14, D15, garde formateur.
4. Install et init : F18, F19.
5. Commentaires : C12, C13 (faux positifs du détecteur de français, priorité : c'est le hook qui refuse le plus).
6. Effort et modèles (1.1).
7. Codex et 97 % (1.2), avec E16 et E17 et la reprise de la phase 0.
   Mesure.
8. CLAUDE.md et rules allégés (1.3). Mesure.
9. `reviewer` découpé, `orchestrate` et `ship` allégés, test-writer continué
   (1.4). Mesure.
10. C11 dans `github.md` (1.5). `/clear` entre deux features : fin de
    `/loop:ship`, hook `SessionStart` sur `clear`, guide (1.9). Mesure.
10b. Agent `implementer`, `test-writer` après le code, `e2e-tester` élargi,
    modèle de `/database:migration` (1.8). Mesure.
11. Skills, cache, addons réduits (1.6).
12. Context7 dans `doc-researcher` (1.7).
13. Mesure finale sur la feature figée, comparée à chaque point intermédiaire,
    et une feature rejouée sur EcoCrew pour confirmer A–F.

## Hors périmètre

- Hooks : changent seulement les points de la partie 2 (bugs, et les nouveaux
  refus A6 et garde formateur), les textes de refus, les checks ajoutés à
  `kit-doctor.py` (B8, D13), le renommage de 1.2 et le marqueur `.token-delegate` de 1.8, le nouveau hook `SessionStart` de 1.9 dans
  `token-statusline.py` et `kit-doctor.py`, et les commentaires qui citaient
  `docs/codex-claude-split-plan.md`. Aucune autre logique de hook ne bouge.
- `product.md` : une fois par produit, sans effet sur le coût d'une feature.
- Commandes bmad : reprises plus tard, y compris l'audit de `bmad/flow.md` (B8).
