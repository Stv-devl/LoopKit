# Workflows — créer une feature

**Une seule boucle**, deux entrées. Prends l'entrée la plus légère qui suffit.

```
                                   /loop:product        (une fois par produit)
                                        │
ENTRÉE COMPLEXE (multi-épics)           ▼
  /bmad:pm ─▶ /bmad:sm ─▶ /stories:review ─▶ /bmad:architect ─▶ /loop:design-system
                                        │
ENTRÉE SIMPLE (1 écran, CRUD)           │
  /loop:spec ───────────────────────────┤
ENTRÉE BUG (symptôme → reproduction)    │
  /loop:debug ──────────────────────────┤
                                        ▼
                              FEATURE READY   (ligne READY du board)
                                        │
BOUCLE (identique pour les deux)        ▼
  /loop:research ─▶ /loop:interface ─▶ /loop:plan ─▶ EXECUTE ─▶ /loop:review ─▶ /loop:ship ─▶ suivante
       └────────────────── /loop:orchestrate enchaîne tout ──────────────────┘
```

`/loop:orchestrate <artefact>` fait tourner la boucle entière. Chaque étape reste
appelable seule si tu veux reprendre au milieu.

**FEATURE READY, concrètement** : c'est `docs/product/backlog.md`, ouvert par
`/loop:product`. **Une ligne par unité de boucle** — une spec fait une ligne, un
pipeline complet en fait une par story. `/loop:spec` et `/stories:review` inscrivent
leurs lignes en `READY` (un contrat ou un slice relu existe derrière) — et
`/loop:orchestrate` aussi, pour le seul cas d'un artefact présent sur le disque et sur
aucune ligne —,
`/loop:product` inscrit en `DRAFT` tout ce qu'il ne fait que recenser — c'est la seule
commande qui écrit cet état, et c'est ce qui rend le gate capable de refuser.
`/loop:orchestrate` refuse d'entrer sur une ligne `DRAFT` et passe celle qu'il prend en
`IN LOOP`, `/loop:ship` la passe en `SHIPPED` et annonce la suivante. Pas de board sur
le disque → l'étape est annoncée sautée, rien ne bloque.

Trois règles font que le board reste lisible au bout de vingt features, et la
**seule copie** des six états, des colonnes et des transitions est `/loop:product`,
section « The board's state machine » — tout le reste la cite :

- **La clé d'une ligne est la cellule `Feature / story`**, jamais le chemin de
  l'artefact — c'est précisément ce qui change quand un `DRAFT` devient une spec.
  `/loop:spec` et `/stories:review` *déplacent* la ligne que `/loop:product` a ouverte, ils
  n'en ajoutent pas une seconde ; sur le pipeline complet, la ligne de la feature
  est *remplacée* par une ligne par story, l'unité de boucle étant la story.
- **Ce que `/loop:product` trouve déjà en production s'inscrit `SHIPPED`**, pas
  `DRAFT`. `DRAFT` veut dire « framé par rien » : l'écrire sur ce qui tourne
  déjà ferait refuser le gate sur du travail terminé.
- **L'ordre des lignes est la priorité**, de haut en bas — le seul endroit du kit
  où une priorité est écrite. `/loop:ship` nomme la **première** ligne `READY`, pas
  « une » ligne `READY` : avec cinq candidates, prendre celle qu'on a lue en
  premier fait passer un accident de lecture pour une décision produit. `/loop:product`
  est la seule commande qui réordonne ; toutes les autres ajoutent **en fin de
  table** et ne déplacent qu'un état. Sur le pipeline complet, `/stories:review`
  remplace la ligne de la feature par ses lignes de story **à la même position,
  dans l'ordre des ids** — le rang porte la priorité, l'ordre des ids porte les
  dépendances.
- **`IN LOOP` se rend.** Cet état affirme qu'une session tient le travail *à cet
  instant* ; seul `/loop:ship` le solde. Toute autre sortie — gate rouge qu'on ne
  reprend pas aujourd'hui, track abandonné, question produit renvoyée à
  l'utilisateur — passe la ligne en `BLOCKED` avec la raison. Sans ça la ligne
  reste `IN LOOP` pour toujours : `/loop:tracks` ne la forke plus, `/loop:ship` ne la
  nomme plus, l'unité disparaît de la boucle en ayant l'air saine. `/loop:ship` liste
  les `BLOCKED` mais n'en propose jamais une comme feature suivante.

**Le profil de token se décide côté produit**, pas au lancement de la boucle :
`/loop:spec` et `/bmad:pm` posent la question fermée (paiement, autorisation,
destruction de données) et écrivent `Token profile:` en tête de leur artefact,
`/bmad:sm` le recopie sur chaque story, `/loop:orchestrate` l'hérite au lieu de
retomber sur `economy`, et `/loop:ship` arme son `/audit:security` dessus. C'est le
seul moment où l'information est connue.

**Le board et le `Status` de story disent la même chose, à deux endroits** :
`READY` ↔ `Approved`, `IN LOOP` ↔ `InProgress`/`Review`, `SHIPPED` ↔ `Done`. Les
deux sont posés ensemble, par `/loop:orchestrate` (Phase 0) ou par `/bmad:dev` (étape
2) selon le chemin, et relus par `/loop:tracks` — qui ne forke **que** des stories
`Approved`. Une story en cours qui reste `Approved` est une story que `/loop:tracks`
proposera à une deuxième session.

Les deux états terminaux sont `SHIPPED` et **`DROPPED`** — livré, ou décidé
contre. Une story tuée au gate `/stories:review` passe `Status: Dropped` et sa
ligne à `DROPPED` : supprimer la ligne ferait passer une décision pour un oubli,
et un id libéré finit toujours par être réutilisé. `DROPPED` a deux autres
rédacteurs, et pas un de plus : `/loop:product` (au refresh) et `/loop:ship` (étape 6),
uniquement pour une décision que tu prends **dans le tour**, jamais déduite d'une
ligne qui a l'air vieille. Dans les trois cas, la ligne **et** le `Status` de la
story bougent ensemble : `/loop:ship` lit la ligne, `/loop:tracks` lit le `Status`, et une
story tuée d'un seul côté revient par l'autre. Sans eux le chemin léger n'avait aucune sortie — une
spec abandonnée restait `READY`, et `/loop:ship` la reproposait indéfiniment.

**Sauf sur un point, et c'est voulu** : `BLOCKED` n'a pas de `Status` à lui. Une
story rendue repasse `Approved` — plus aucune session ne la tient, et c'est
exactement ce que ce champ dit — et c'est la **ligne du board** qui porte la mise
en attente. `/loop:tracks` lit donc les deux et écarte les lignes `BLOCKED` : sans ça
une story mise de côté serait reforkée dès le passage suivant.

**`/loop:design-system` est un prérequis dur de `/loop:interface`**, pas une option : sans
`docs/design-system.md`, les propositions inventent des composants au lieu de
composer avec les primitives existantes. Écrit une fois, rafraîchi quand le kit
bouge.

Il a **deux modes**, détectés automatiquement (`--new` / `--extract` pour forcer) :

- **`extract`** — le système est déjà dans le code. 4 explorers le lisent, la
  commande l'écrit. C'est le cas normal, et le seul après la première story.
- **`bootstrap`** — produit démarré de zéro, rien à lire. Interview, puis 3
  `designer` en mode `system` proposent chacun un système complet (tokens +
  primitives + 2 écrans de référence), les 3 previews sont publiées en artifacts,
  et **c'est toi qui tranches** : une direction visuelle est un choix de goût et
  de positionnement, les agents n'ont pas d'yeux. Le canvas n'entre qu'**après**
  ce choix, sur le gagnant : convertir les trois ferait ré-écrire par un modèle
  exactement ce qui est en train d'être jugé. Le gagnant devient
  `docs/design-system.md` + les tokens réels ; **aucun composant React n'est
  écrit ici**, ils arrivent par les stories, avec leurs tests.

`bootstrap` ne tourne qu'**une fois dans la vie d'un produit**. Dès que
`docs/design-system.md` existe, le code reprend la main et tout est `extract`.

---

## Entrée simple (défaut)

```bash
/loop:spec ma feature                     # interview → docs/specs/<slug>.md (le contrat)
/loop:orchestrate docs/specs/<slug>.md    # research → interface → plan → execute → review → ship
```

`/loop:spec` pose 3-4 questions, écrit le contrat, **s'arrête** — tu relis les critères
d'acceptation avant que quoi que ce soit ne parte.

## Entrée complexe

```bash
/bmad:flow ma grosse feature         # enchaîne tout, avec pauses de validation
```

Ou étape par étape (chaque commande marche seule) :

```bash
/bmad:pm ma feature                      # → docs/prd/<slug>.md
/bmad:sm docs/prd/<slug>.md              # → stories FONCTIONNELLES, en Draft
/stories:review docs/stories/<slug>/     # gate parallèle → stories Approved
/bmad:architect docs/prd/<slug>.md       # → docs/architecture/<slug>.md
/loop:orchestrate docs/stories/<slug>/1.1.md  # la boucle, story par story
```

> **Les stories passent avant l'archi.** Une story mal découpée se réécrit en 2
> minutes tant qu'elle est fonctionnelle ; après une archi construite dessus, elle
> coûte une journée. `/stories:review` la tue avant.

Le contexte technique (chemins, contrats, pièges) n'est pas recopié par le SM :
c'est `/loop:plan` qui l'injecte dans la story, au moment où il est frais et sourcé
par `/loop:research`.

Statuts d'une story : `Draft → Approved → InProgress → Review → Done`, plus
`Dropped` (terminal, posé par `/stories:review`).

### Story d'un trait, ou dev/QA séparés

Deux façons de faire tourner une story `Approved` :

```bash
/loop:orchestrate docs/stories/<slug>/1.1.md   # d'un trait : boucle complète, ship inclus
```

```bash
/bmad:dev docs/stories/<slug>/1.1.md      # boucle SANS ship → Status Review
/bmad:qa  docs/stories/<slug>/1.1.md      # gate → PASS / CONCERNS / FAIL
/loop:ship     docs/stories/<slug>/1.1.md      # seulement si PASS
```

La seconde te rend la main entre le code et le gate : sur `CONCERNS`/`FAIL`, tu
reboucles `/bmad:dev` → `/bmad:qa` jusqu'au `PASS`. `/bmad:dev` tient aussi le
carnet de bord de la story (Status, Dev Agent Record, Change Log).

Prends `/loop:orchestrate` quand la story est balisée, la boucle dev/QA quand tu veux
un point d'arrêt avant le commit.

---

## Budget de tokens et reprise Codex

Le profil est choisi une fois par track et écrit dans chaque artefact
`docs/work/<slug>/` :

| Profil | Usage |
| --- | --- |
| `economy` | défaut ; sondes et reviews groupées, synthèse dans le contexte principal |
| `standard` | surfaces indépendantes ou ambiguïté réelle |
| `critical` | paiement, autorisation, données destructives, ou demande explicite |

Le profil ne réduit jamais les gates mécaniques (typecheck, lint, tests,
coverage, build, `audit`). Il réduit les relectures identiques par plusieurs
modèles.

**Il en ajoute un, dans un sens seulement.** `critical` arme un `/audit:security`
d'**une** surface à `/loop:ship` (étape 1bis) : la liste qui justifie `critical` est
mot pour mot celle des features où une barrière serveur manquante n'est pas un
Minor. Descendre une feature en `economy` pour éviter cet agent est une décision
de sécurité, pas de budget — `.claude/rules/11-token-budget.md`.

Le chemin recommandé lance Claude sous supervision :

```bash
./workflow.sh
```

La status line crée trois seuils : checkpoint à 90 %, aucun nouveau sous-agent
à 95 %, puis relais Codex à 97 %. Le superviseur interrompt Claude à la frontière
atomique suivante et lance Codex sur `handoff-codex.md`. Il déclenche aussi le
relais quand la sortie Claude annonce une limite d'usage.

Pour le quota d'abonnement affiché par le CLI : 90–94 % arme le checkpoint sans
couper Claude ; 95 % déclenche le relais. Le motif est configurable avec
`CLAUDE_WORKFLOW_QUOTA_WARNING_REGEX` si le libellé local diffère.

Relais manuel avant une limite :

```bash
/handoff:codex docs/work/<slug>/plan.md
./codex-handoff.sh docs/work/<slug>/handoff-codex.md
```

Après une coupure brutale, le checkpoint est optionnel :

```bash
./codex-handoff.sh docs/work/<slug>/plan.md
# accepte aussi research.md, une story ou une spec
```

Le script ouvre Codex dans le projet avec un sandbox `workspace-write` et les
approbations `on-request`. Il ne fixe aucun modèle : la configuration Codex de
l'utilisateur reste l'autorité. `AGENTS.md` lui demande de lire le dernier
artefact, de ne pas refaire les phases terminées et de respecter les règles TDD.

**Bascule délibérée, distincte du relais de saturation.** Le relais ci-dessus se
déclenche sur un signal externe (quota, contexte), jamais par choix.
`.claude/workflow-routing.yml` porte une répartition séparée : les rôles
`execute-green` (implémentation une fois plan et tests gelés) et `review-fixes`
(correctif d'un finding Critical/Major déjà tranché par `reviewer`/`verifier`)
partent par défaut sur Codex à `codex_effort: low` — du mécanique, jamais du
jugement. `/loop:orchestrate` lit ce fichier aux deux frontières concernées et
retombe sur Claude sans rien changer si le fichier est absent, si
`command -v codex` échoue, ou si `--inline-execute` est passé. Détail et
justification du choix de ces deux frontières précises :
[`docs/codex-claude-split-plan.md`](codex-claude-split-plan.md).

## Les étapes de la boucle

| Commande    | Ce qu'elle fait                                                               | Produit                        |
| ----------- | ----------------------------------------------------------------------------- | ------------------------------ |
| `/loop:research` | Fan-out multi-modal : code, blast radius, **état réel en base**, API tierces  | `docs/work/<slug>/research.md` |
| `/loop:interface` | Propositions UI concurrentes (nombre = profil de tokens), rendues sur un **canvas éditable**, puis **tu choisis** : gate humain. SKIP si pas d'UI | `docs/work/<slug>/design.md`   |
| `/loop:plan`     | Chaîne d'écriture + lots + contrats + plan de test, puis `plan-critic` (complétude et qualité séparées) | `docs/work/<slug>/plan.md` |
| EXECUTE     | Inline, séquentiel, dans l'ordre du plan (les écritures sont couplées)        | le code                        |
| `/loop:review`   | Étage 0 : passe visuelle (UI) · Étage 1 : 5 dimensions · Étage 2 : réfutation | verdict PASS/CONCERNS/FAIL     |
| `/loop:ship`     | Gates parallèles, commit via l'agent `github`, board à jour, feature suivante | le commit                      |

Deux commandes bornées vivent autour de cette boucle : `/loop:spike` tranche une
question fermée (ou retourne `indeterminate` avec la preuve manquante), et
`/kit:recipe` transforme une procédure déjà prouvée en guide froid cité par un
seul caller. Sur profils standard/critical, la review ajoute une passe
shadow-areas de trois éléments maximum ; economy reste silencieux.

**Deux étapes s'arrêtent sur toi, et elles décident deux choses différentes.**
`/loop:interface` te présente ses propositions et attend que tu tranches (greffe possible,
3 tours maximum) : ça fixe **ce qu'est l'écran**, et c'est ce qui rend honnête le
fait que `/loop:review` note ensuite un écart en Major. `/loop:plan` imprime son `Test plan`
et attend ton feu vert : ça fixe **ce que « correct » veut dire pour la logique**,
et c'est le dernier moment gratuit — juste après, ces fichiers de test gèlent.
Avant de te le présenter, `plan-critic` cherche les omissions et les défauts
d'exécution sur deux scores indépendants ; tout Critical/Major est réfuté puis
corrigé. Chaque gate est plafonné à trois échecs dans `attempts.json` : au
troisième, la ligne revient `BLOCKED` avec le gate et sa raison.
Aucune ne remplace l'autre, aucune ne passe sur ton silence. Les gates de `/loop:ship`
(push, PR, merge) et celui de `/loop:tracks` sont d'une autre nature : ils décident ce
qui **sort de la machine**, jamais ce qu'elle doit produire.

### Le canvas de `/loop:interface`, et pourquoi la commande ne s'appelle pas `/design`

Claude Code embarque sa propre skill **`/design`** (research preview) : elle publie
un canvas pan/zoom en Artifact, un *artboard* par écran, et — là où la sauvegarde
est activée sur le compte — tu y sélectionnes un élément, tu édites le texte en
place, tu annules, tu réorganises, tu enregistres. C'est exactement la jambe qui
manquait à l'étape : les agents `designer` raisonnent sur la structure, les états
et le comportement, et ils l'écrivent noir sur blanc — **ils ne voient rien**.

Trois conséquences, et elles sont l'essentiel de l'intégration :

1. **La commande du kit a déménagé.** Une commande projet nommée `design` masque
   la skill intégrée, et l'étape *l'appelle*. Elle s'appelle donc `/loop:interface` —
   ce que son titre disait déjà. L'artefact reste `docs/work/<slug>/design.md`, la
   dimension du `reviewer` reste `ui`, `/loop:design-system` ne bouge pas.
2. **Le kit ne fabrique jamais le canvas lui-même.** La skill possède un payload
   précompilé et un helper dont le chemin n'existe que pendant son exécution :
   toute opération (rendu, re-seed après une greffe, relecture) passe par elle,
   depuis le thread principal. Le kit lui donne un brief — le design system
   extrait, la proposition retenue, les écrans et leurs tailles de cadre, la
   langue, l'interdit d'icônes — et récupère un lien.
3. **Le canvas est un miroir, `design.md` reste le contrat.** Passé le gate, le
   document gèle et le canvas, lui, reste éditable sans que rien ne surveille.
   `/loop:review` compare le diff à `design.md` et note un écart en Major : un canvas
   qui bouge après coup déplace l'image, jamais la référence. Une modification
   après le gate **rouvre le gate**, sinon c'est de la décoration. Et rien ne
   descend du canvas vers le code : un artboard est une maquette, le code entre
   par `/loop:plan` et EXECUTE, avec ses tests.

Le canvas est une research preview (login claude.ai first-party, `node` ou `bun`
sur la machine). Indisponible, l'étape le dit en une ligne et le gate se tient sur
les propositions textuelles, comme avant. La jambe se dégrade, le gate jamais.

À ne pas confondre avec `DesignSync`, que `/loop:design-system` utilise déjà : ça, ce
sont les **projets design-system** de claude.ai/design, l'index de cartes
`@dsCard`, la vitrine du document. Deux surfaces, aucune ne lit l'autre.

Chaque étape est appelable seule, donc tu peux **reprendre au milieu** : après un
fix à la main, `/loop:review <artefact>` relance juste le gate ; après une review,
`/loop:ship <artefact>` juste la clôture. La boucle lit ses artefacts sur disque
(`docs/work/<slug>/`), pas la conversation — un contexte neuf reprend où tu en
étais.

Le `<slug>` se **déduit du chemin de l'artefact d'entrée** (`docs/specs/inbox.md`
→ `inbox` ; `docs/stories/inbox/1.2.md` → `inbox-1.2`), et `/loop:research` est l'étape
qui l'**enregistre**, en créant le dossier. Les étapes suivantes le lisent dans le
chemin qu'on leur passe plutôt que de le redéduire : deux orthographes = un
`/loop:plan` qui ne trouve aucune research et repart de zéro.

Une exception, et elle est structurelle : `/loop:tracks` et la Phase 0.5
d'`/loop:orchestrate` nomment le worktree et la branche **avant** que `/loop:research` ait
tourné. Elles appliquent donc la déduction elles-mêmes — c'est tout l'intérêt
qu'elle soit une fonction du chemin. Sur une story c'est `inbox-1.2`, **jamais**
`inbox` : trois stories forkées sous le slug de la feature, c'est trois tracks
dans un seul worktree.

## Le TDD, dans EXECUTE

Trois couches sont écrites **test d'abord** : `utils.ts`, `mapper.ts`,
`repository.ts`/`services.ts`. Pas les hooks, pas l'UI — leur contrat bouge
encore. C'est la partie de la boucle qui a le plus de mécanique, parce que c'est
celle qu'un agent contourne le plus volontiers.

| Moment | Ce qui tient la règle |
| --- | --- |
| Liste des cas | Le **gate humain de `/loop:plan`** : le `Test plan` est imprimé et attend ton feu vert. C'est le dernier endroit où la définition de « correct » est gratuite à changer. |
| Écriture du test | L'agent **`test-writer`**, un par couche. Il reçoit les `Contracts` et son bloc du plan, et il lui est **interdit d'ouvrir le module** qu'il teste. |
| Le rouge | `tdd-prove-red.sh` (PostToolUse) lance le fichier et compare les **symboles** testés à ce que le module exporte réellement. Un test qui passe alors que le comportement nommé n'existe pas est signalé comme n'assertant rien. |
| Le passage au code | `tdd-require-red.sh` (PreToolUse) **refuse de créer** le module tant que ce rouge n'a pas été constaté. C'est le seul endroit où « implémentation avant test » devient impossible. |
| Après le vert | `tdd-freeze-tests.sh` gèle le fichier. **Ajouter** un cas passe (insertion pure). **Corriger** un cas est refusé → `.claude/.tdd-unfrozen`, avec une raison, visiblement. |
| Le contournement | Les trois hooks ci-dessus ne voient que `Write` et `Edit`. `prevent-destructive-commands.sh` ferme la porte de derrière : écrire une de ces couches ou un fichier de test **depuis le shell** (`>`, `tee`, `sed -i`) est refusé, ainsi qu'un `-u` de snapshot nommant un fichier gelé — là c'est le *runner* qui réécrit le test. Tout autre `.ts` écrit au shell repasse par ta validation. |
| Au gate | La dimension `tests` de `/loop:review` compare les fichiers gelés au plan validé : cas supprimé, affaibli ou renommé = **Major**, gel contourné = **Critical**. |

**Une couche à la fois**, RED→GREEN, dans l'ordre des dépendances — jamais trois
rouges d'un bloc puis trois verts. Écrire tous les tests avant tout code est la
lecture fausse la plus répandue du TDD : l'implémentation est alors générée
contre une douzaine d'assertions rouges simultanées, « juste assez de code »
n'est plus jugeable, et une assertion fausse ne se découvre qu'après le gel.
La *liste* des cas, elle, s'écrit bien en entier d'avance — c'est l'analyse, et
c'est ce que `/loop:plan` te fait valider.

Deux règles de contenu qui valent pour toutes les couches : on asserte le
**comportement** (la valeur rendue, l'effet observable), jamais qu'un mock a été
appelé ; et on ne mocke jamais une fonction pure. Détail :
`.claude/rules/05-testing.md`.

**Où l'on mocke, et avec quoi.** Chaque couche mocke celle juste en dessous —
sauf le `gateway.ts`, qui *est* le transport : lui se mocke au réseau, avec
**MSW** (`patterns/msw.md`), le vrai client tournant et la requête inspectable.
Un faux client chaîné à la main ne teste pas le gateway, il le récite. MSW sert
aussi de couche mock aux specs Playwright qui doivent muter sur une surface
read-only — jamais par défaut sur toute la suite E2E.

**Ce que rien ne vérifie dans la boucle** : que les fichiers gelés contraignent
vraiment le code. Le coverage dit qu'une ligne a été exécutée, pas que la
supprimer casserait quelque chose. C'est le rôle de `/audit:mutation`, hors
boucle, jamais en gate.

## Hors boucle

| Commande              | Quand                                                             |
| --------------------- | ----------------------------------------------------------------- |
| `/database:migration` | Toute migration SQL — jamais de SQL écrit à la main               |
| `/audit:security`     | Ce qui est exposé **aujourd'hui**, sur tout le dépôt — pas sur un diff. Armé aussi par `/loop:ship` sur profil `critical`, une surface |
| `/audit:mutation`     | Est-ce que les tests gelés **contraignent** le code, ou se contentent-ils de l'exécuter ? |
| `/audit:part <nom>`   | Est-ce que **cette partie-là** (react-query, zustand, ci-cd, testing, forms, guardrails…) est cohérente, vraie et réellement appliquée ? Fan-out sur des fichiers disjoints, **réfutation obligatoire** de chaque constat, registre dans `docs/audits/<partie>.md`. Le premier passage est un échantillon ; tous les suivants sont un diff |
| `/refactor:split`     | Un fichier dépasse son seuil (`.claude/rules/02-architecture.md`) |
| `/refactor:clean`     | Code mort : exports, dépendances et variables inutilisés          |
| `/refactor:types`     | Resserrer des types, éliminer un `any` résiduel                   |
| `/kit:doctor`         | Les valeurs écrites deux fois (règle + copie appliquée) sont-elles encore d'accord ? Plus les chemins, hooks et commandes morts |

<!-- FILL : ajoute ici les commandes propres à ce projet (une skill qui pilote
     ton API, un script de déploiement…). -->

## Addons

Le kit est front-end par défaut. Deux overlays couvrent un backend réel — même
boucle, mêmes agents, des règles et des commandes en plus :

| Addon | Ce qu'il apporte |
| ----- | ---------------- |
| `addons/supabase/` | Règles stack + DB (RLS incluse), `/database:migration` version Supabase, patterns front (client, types générés, realtime, storage) et edge functions, plus le layer `_shared/` livré en code testé |
| `addons/fastapi/` | Règles backend + DB (SQLAlchemy/Alembic), 13 commandes `/backend:*`, `/database:migration` version Alembic, patterns FastAPI (archi, auth, config, upload, pytest, RAG ingestion + retrieval + SSE), 3 hooks Python |

```bash
./install.sh /chemin/vers/projet --fastapi     # ou --supabase, ou les deux
```

L'installation copie les fichiers. Sur une install **neuve**, elle câble en plus
ce qu'elle peut : `--fastapi` déclare les six hooks Python dans `settings.json`,
`@07-backend.md` dans l'index de `CLAUDE.md` et `app|alembic` dans
`PROTECTED_DIRS` ; `--supabase` pointe `DATA_CLIENT_MODULE` /
`DATA_CLIENT_OWN_PATH` sur `lib/supabase` et ajoute `supabase` à
`PROTECTED_DIRS`. Uniquement des fichiers que le kit vient d'écrire, jamais un
fichier préexistant (il repart en `.new`).

Chaque valeur ainsi câblée est écrite **deux fois** — le hook l'applique,
`CLAUDE.md` ou une règle la déclare — et l'installeur patche les deux copies.
C'est `/kit:doctor` qui vérifie qu'elles n'ont pas divergé depuis.

**Le reste du câblage est à faire à la main**, décrit dans le README de l'addon
(recopié en `.claude/skills/patterns/<NOM>-ADDON.md`) : `EXTERNAL_CLIENTS` dans
`enforce-backend-layers.py`, la table du client dans `01-stack.md`, les scripts
de `00-project.md`, et les deux que personne ne pense à faire — **les gates
backend dans `commands/ship.md`** (le bloc est en `pnpm`, il ne teste rien sur un
repo Python) et **`07-backend.md` dans les dimensions de `agents/reviewer.md`**.
Non câblé = installé mais muet.

Côté boucle, rien ne change : `/loop:interface` se saute quand il n'y a pas d'UI, les
commandes `/backend:*` sont ce qu'EXECUTE utilise pour construire, et les
commandes d'audit (`/backend:audit`, `security`, `perf`, `rag-audit`) sont ce
qu'un finding de `/loop:review` devient quand une dimension doit creuser.

## Ce qui tourne en parallèle

**Partie produit (amont)**

- **`/loop:product`** : 1 explorer groupe front, backend et data ; un second seulement pour une base distante.
- **`/bmad:pm`** : 1 explorer couvre l'existant, les contraintes réelles et
  l'antériorité ; un second n'est permis que pour des surfaces réellement
  indépendantes.
- **`/bmad:sm`** : la découpe est décidée et, jusqu'à 8 stories, écrite dans le
  contexte principal. De 9 à 16, 2 writers ; au-delà, lots de 6–8.
- **`/stories:review`** : 1 critic jusqu'à 6 stories, 2 jusqu'à 12, 3 maximum
  au-delà. Chaque lot contrôle aussi la couverture depuis le catalogue global.
- **`/bmad:architect`** : fan-out de cartographie ; la rédaction reste en un seul
  contexte (une archi doit être cohérente, pas rapide).
- **`/loop:design-system`** : mode `extract`, 4 explorers (tokens, primitives,
  composition, états) ; mode `bootstrap`, 3 `designer` sur des répertoires
  candidats disjoints, puis **tu juges** — pas d'agent juge.

**Boucle**

- **`/loop:research`** : 3 sondes de base, les sondes obligatoires déclenchées par la
  surface touchée (migration superseded, consommateurs d'un symbole, module
  backend partagé…), la sonde base réelle et la doc externe.
- **`/loop:interface`** : 3 angles (minimal / densité / guidé) + 1 juge.
- **`/loop:debug`** : reproduction isolée avant tout fix, causes candidates
  classées, logs temporaires de validation, puis cause prouvée.
- **`/loop:review`** : 5 dimensions **+ 1 `e2e-tester` par flux** dans le même message,
  puis 1 réfuteur par finding Critical/Major.
- **`/loop:ship`** : `typecheck` + `lint` (`--max-warnings=0`) + tests (run-once) +
  `coverage` + `build` + `pnpm audit` + le grep des `VITE_*` secrets, lancés
  ensemble. Le `lint` n'est pas décoratif : c'est le seul qui voie un test sans
  assertion, un `it.only` et un composant que le compilateur React a sauté. Les
  deux dernières lignes non plus : une CVE publiée cette semaine ne change rien
  au diff, donc aucune relecture ne peut la voir (`.claude/rules/00-project.md`).
  Puis, **sur profil `critical` uniquement**, un `security-auditor` d'une surface
  avant le commit (étape 1bis) — zéro sur les deux autres profils.

**Hors boucle**

- **`/audit:security`** : 2 auditeurs groupés en `economy`, 3 en
  `standard`, ou 6 surfaces séparées en `critical`, puis réfutation par lots
  avec le `verifier` existant. Ce n'est pas la dimension `security` de `/loop:review` : celle-ci
  juge un diff dans la boucle, celui-là lit le dépôt entier, y compris le code que
  personne n'a touché depuis six mois.
  **Un seul appelant automatique** : `/loop:ship` sur profil `critical`, pour une
  surface. Partout ailleurs il reste à la demande, et il n'écrit jamais rien —
  les correctifs repassent par la boucle avec leurs tests.

Le principe est : **on parallélise les informations indépendantes**, pas la
relecture répétée d'une même source. Des fichiers disjoints rendent l'écriture
sûre, mais ne rendent pas automatiquement un agent par fichier économique.
`/bmad:sm` et `/stories:review` travaillent donc par lots bornés ; EXECUTE
reste en chaîne parce que le code est couplé.

Ce qui **ne** se parallélise **pas** : EXECUTE. Deux agents qui écrivent des
fichiers couplés coûtent plus cher que l'attente. Seuls les _lots_ déclarés
disjoints par `/loop:plan` peuvent forker.

## Worktrees — plusieurs travaux en même temps

Deux niveaux, à ne pas confondre :

| Niveau | Unité | Isolation |
| --- | --- | --- |
| **Dans** une passe de boucle | les _lots_ de `/loop:plan` | aucune — des agents dans le même arbre, fichiers disjoints |
| **Entre** passes de boucle | une **track** (1 spec, 1 story) | **1 worktree + 1 branche** : `.claude/worktrees/<slug>`, `feat/<slug>` |

Le fork se décide en **Phase 0.5 de `/loop:orchestrate`**, une fois, et seulement si
les quatre conditions tiennent : ≥ 2 tracks en vol, fichiers disjoints, aucune
**fondation partagée** touchée, arbre propre. Une feature seule reste dans
l'arbre principal — le setup ne rembourse rien.

**Combien de tracks, ce n'est pas « deux » par défaut** : ça se calcule contre
l'état du dépôt au moment où on le demande, et ça change après chaque merge.
C'est le rôle de **`/loop:tracks`** — il calcule, il vérifie, il prépare les
worktrees, et il se relance après chaque merge plutôt que de se rappeler du
compte précédent.

```
/loop:tracks docs/stories/<slug>/
```

Quatre étapes, dans cet ordre — débloquées par dépendance (un prérequis
`Approved` ou fini-mais-non-mergé ne compte pas), puis **une seule migration en
vol**, puis **un seul écrivain par fichier partagé**, puis le coût (une story de
deux fichiers n'amortit pas un checkout vide). **Plafond : trois.** Ce n'est pas
une limite arithmétique mais une limite de pilotage — une session tient un
worktree, donc N tracks = N sessions ouvertes, N installs, N `.env` copiés à la
main, et une barrière d'intégration qui reste strictement une à la fois.
Une quatrième survivante n'est pas jetée, elle est **mise en file**, nommée
derrière la track qui mergera la première.

La commande annonce le nombre, l'ensemble nommé, et pourquoi chaque autre
candidate est exclue — une exclusion que personne n'a écrite revient en conflit
de merge. La création des worktrees est **gatée** : elle attend ton go.

Et la colonne `Parallel with` de la story map est une indication, pas un
verdict : elle est écrite avant le code et elle dérive. `/loop:tracks` ouvre les
fichiers qu'elle nomme, et quand le code la contredit, **c'est le code qui
gagne** — la story map est corrigée dans la même passe. Méthode complète :
`.claude/guides/10-worktrees.md`, « How many tracks ».

Les fondations partagées ne forkent **jamais** : migrations et base réelle (un
worktree isole des fichiers, pas un schéma), `src/lib/*`, `shared/*`, le router
et les providers, `docs/design-system.md`, le backlog, le lockfile. Elles se font
**d'abord, dans l'arbre principal**, et les tracks forkent depuis ce commit. En
pipeline complet, c'est la colonne « Shared foundations » de la story map de
`/bmad:architect` qui tranche.

**Avec quoi on fork** :

| Besoin | Outil |
| --- | --- |
| Cette session travaille sur la track | `EnterWorktree` (`name: <slug>`) — crée, entre, propose keep/remove en sortie |
| Pré-créer une track sœur sans quitter la sienne | `git worktree add .claude/worktrees/<slug> -b feat/<slug>` |
| Entrer dans un worktree existant | `EnterWorktree` (`path: …`) |
| Sortir | `ExitWorktree` (`keep` \| `remove`) |
| Un job mécanique sans gate (codemod, bump de dépendance) | un `Agent` en `isolation: "worktree"` |

Une passe de boucle n'est **jamais** un sous-agent isolé : elle a des gates
humains (design jugé, findings corrigés, ship validé) qu'un sous-agent ne peut
pas tenir. **Une session est dans un seul worktree à la fois** — deux features
réellement menées de front, c'est deux sessions. La session courante crée le
worktree sœur, le nomme, et te le passe ; elle ne fait pas semblant de piloter
les deux.

Les garde-fous suivent tout seuls : `.claude/` est versionné, donc le checkout du
worktree embarque ses hooks et ses règles. Le point de départ des branches, lui,
est un réglage : `worktree.baseRef` dans `settings.json` — le kit livre `head`
(dépôt local sans origin), à passer en `fresh` sur un repo d'équipe.

L'intégration est une **barrière, une track à la fois** : rebase → gates re-passés
si le rebase a bougé quelque chose → ton feu vert → merge → suppression du
worktree. Un merge est aussi gaté qu'un push, et l'agent `github` l'exécute.

Deux coûts à annoncer avant de forker : le worktree est vide de `node_modules`,
et le `.env` **ne peut pas être copié par un agent** (`protect-files`) — c'est à
toi de le déposer.

Règle complète : `.claude/guides/10-worktrees.md`.

---

## Les agents

| Agent          | Rôle                                                                            | Écrit ?   |
| -------------- | ------------------------------------------------------------------------------- | --------- |
| `explorer`     | Cartographie read-only (patterns, wiring, réutilisable)                         | non       |
| `story-writer` | Écrit un lot borné de stories depuis le PRD — fonctionnel, jamais technique     | 1 lot de fichiers |
| `story-critic` | Juge un lot de stories et la cohérence globale depuis leur catalogue            | non       |
| `designer`     | Propose une UI sur un angle imposé, juge les 3 propositions, ou (mode `system`) propose un design system entier | son dossier candidat, en mode `system` uniquement |
| ↳ ce qu'il a   | `frontend-design`, le design system, 2 vraies pages du produit — **pas d'yeux** | —         |
| `test-writer`  | Écrit UN fichier de test test-first, le lance, rend la sortie d'échec — sans jamais lire le module testé | 1 fichier |
| `reviewer`     | Review adversariale sur 1 dimension                                             | non       |
| `e2e-tester`   | Écrit et lance UN spec Playwright — prouve un flux en vrai navigateur           | 1 spec    |
| `verifier`     | Tente de **réfuter** un finding — ce qui survit est réel                        | non       |
| `security-auditor` | Audit sécurité d'UNE surface, sur le dépôt entier — hors boucle            | non       |
| `github`       | Commits locaux ; tout ce qui touche GitHub demande ton accord                   | oui       |

---

## Règles communes (rappel)

<!-- FILL : cette section doit refléter `.claude/rules/`. Si tu changes une règle
     là-bas, change-la ici — c'est le rappel que tout le monde lit. -->

- Migrations : jamais de SQL à la main → `/database:migration`.
- Pas d'import cross-feature, pas de logique métier dans pages/composants.
- Client de données uniquement dans `gateway`/`services` ; hooks → repository
  (`Result<T>`).
- Pas de `any` ; messages user dans la langue produit, logs/erreurs **EN** ;
  états React Query gérés.
- Dans un gate ou un agent : le script de test **run-once**, jamais le mode watch
  (il ne rend jamais la main).
- Travaux séparés = worktrees séparés ; fondations partagées d'abord, dans
  l'arbre principal ; merge une track à la fois, avec ton accord.

Détails : `.claude/rules/` · patterns : `.claude/skills/patterns|templates/`.
