# Adapter le kit à un projet

Source ordonnée de `/kit:init`, section par section. L'utilisateur lance la
commande ; il n'a plus à parcourir cette checklist à la main. Elle reste la
référence détaillée pour maintenir ou auditer l'adaptation.

Le kit est générique **par construction** : chaque endroit à adapter porte un
commentaire `<!-- FILL: … -->`. Tant qu'un marqueur est là, la règle
correspondante ne protège rien.

```bash
grep -rnE "FILL|CONFIGURE" .claude/ CLAUDE.md docs/
```

21 fichiers en contiennent. Dans l'ordre où ça compte :

## 1. `.claude/rules/01-stack.md` → tableau « The data client »

La pièce maîtresse. Où vit le client, qui a le droit de l'importer, quelle est la
vraie barrière d'autorisation **côté serveur**. Les dimensions `correctness`,
`security` et `db` de l'agent `reviewer` lisent ce tableau ; un tableau vide, et
la review gate contre du vide.

## 2. `.claude/hooks/enforce-architecture.py` → `DATA_CLIENT_MODULE` + `COMPOSITION_ROOTS` + `SHARED_DIRS`

`DATA_CLIENT_MODULE` doit correspondre au point 1, sinon le hook garde une porte
qui n'existe pas. `None` désactive ce contrôle (cross-feature et shared→feature
restent actifs).

`COMPOSITION_ROOTS` liste les fichiers qui **créent** l'instance du client et
l'injectent dans le contexte routeur/provider — par défaut `main.tsx` et
`routes/__root.tsx`. Ce sont les seuls, hors couche data, autorisés à l'importer.
Si ton point d'entrée est ailleurs, corrige la liste ici **et** le tableau
« composition root » de `02-architecture.md` : c'est le même contrat écrit deux
fois, une fois pour la machine, une fois pour l'agent.

`SHARED_DIRS` est la troisième, et elle a **quatre** copies, pas deux : le tuple
du hook, les deux listes d'import de `02-architecture.md`, la case « shared
leaf » de `.claude/agents/reviewer.md` — qui en donne aussi le **nombre** — et la
ligne « code partagé » de `CLAUDE.md`. Le kit livre six entrées —
`components/ hooks/ lib/ types/ stores/ config/`. `providers/` et `routes/` en
sont volontairement absents : ce sont des câblages, ils ont le droit de connaître
les features qu'ils composent. Ajoute un répertoire feuille à ton arborescence
(`src/constants/`, `src/utils/`…) et il faut le mettre aux quatre endroits —
oublier le reviewer est le plus coûteux des quatre, parce que le hook n'inspecte
que le **delta inséré** d'un Edit : un import déjà présent ailleurs dans le
fichier ne lui arrive jamais, et le reviewer est alors le seul filet.

`/kit:doctor` compare désormais le tuple à **trois** de ces copies — la liste
« Forbidden » de `02-architecture.md`, `CLAUDE.md`, `reviewer.md` — plus le
compte que le reviewer annonce en toutes lettres (`check_shared_dirs`). La liste
« Allowed from anywhere » de `02-architecture.md` reste **manuelle** : elle est
énumérative et non miroir du tuple (`providers/` y figure, pas dans
`SHARED_DIRS`). La synchronisation reste à ta charge, mais l'oubli ne passe plus
en silence.

### 2 bis. `ENV_TEMPLATE_RE` → la seule constante écrite deux fois sans filet

`protect-files.sh` (`ENV_TEMPLATE_RE`) et `prevent-destructive-commands.sh` (le
sanitizer de `SECRET_RE`) décident tous les deux quels suffixes `.env` ne portent
aucun secret — le kit livre `example|sample|template` des deux côtés. Si ton repo
utilise une autre convention (`.env.dist`, `.env.tpl`), **change les deux**. Une
seule des deux modifiée, et les outils et le shell cessent de protéger le même
ensemble : `Read .env.dist` refusé, `cat .env.dist` autorisé, ou l'inverse.

Ces deux-là ne sont pas des `FILL` mais des `CONFIGURE`, comme les sept autres
constantes câblées dans les hooks — c'est pour ça que la commande d'inventaire
en tête de ce fichier cherche **les deux mots**.

## 3. `src/lib/result.ts` + `src/lib/errors.ts` + `src/lib/queryClient.ts` → à scaffolder

Pas un `FILL`, mais le prérequis le plus souvent oublié. Tous les patterns du kit
importent `Result<T>`, `unwrap`, `ServiceError` et `formatServiceError`. Copie-les
depuis `.claude/skills/templates/lib-core.md` **avant la première feature** :
sans eux, chaque feature réinvente sa propre forme d'erreur et la frontière
`Result<T>` ne veut plus rien dire.

Le troisième, `queryClient.ts`, vient du même template et se fait oublier pour
une raison inverse : sans lui l'app **démarre quand même**, sur les défauts de
React Query. Ce sont les mauvais ici — `staleTime: 0` (chaque montage refetch) et
`retry: 3` sur un `not_found` que `unwrap` vient de lever, soit plusieurs
secondes de backoff avant que l'état d'erreur s'affiche.

Ajoute `src/lib/userMessages.ts` dans la foulée (`patterns/feedback.md`) : c'est
le seul endroit où un `code` devient de la copie utilisateur. Les codes propres à
une feature s'écrivent dans la **même casse** que les codes canoniques — en
minuscules — sinon ils ne matchent jamais et tout ressort en message générique.

> **Piège de nommage, pendant qu'on est dans `src/lib/`** : un `src/lib/utils.ts`
> nu est une couche test-first pour les hooks TDD, donc sa création est refusée
> tant qu'un rouge n'est pas constaté — et c'est exactement là que shadcn/ui pose
> son helper `cn()`. Mets-le en `src/lib/utils/cn.ts` (ce qu'importe
> `templates/component.md`), ou déclare-le dans `.claude/.tdd-unfrozen`.

## 4. `.claude/rules/00-project.md` → les scripts

`dev`, `build`, tests **run-once**, `typecheck`, `lint`, **audit de
dépendances**. Un gate ne peut pas inventer un script absent — et s'il tombe sur
le mode watch, il ne rend jamais la main. `lint` compte : le hook eslint est
**non bloquant**, donc sans script de lint dans `/loop:ship`, les règles que seul
ESLint voit (hooks conditionnels, exhaustive-deps) ne bloquent jamais rien.
L'audit de dépendances compte pour la raison inverse : c'est le seul gate qui
puisse virer au rouge **sans qu'un octet du dépôt ait changé**, donc le seul que
ni une relecture ni un test ne remplacent. Pas de `pnpm` ? Nomme l'équivalent
(`npm audit`, `yarn npm audit`, `pip-audit`) ; pas d'équivalent, dis-le.

Le script run-once est aussi codé en dur dans `.claude/hooks/tdd-prove-red.sh`
(`RUN_TESTS`) : si le tien ne s'appelle pas `pnpm test:run`, change-le là aussi.
Le hook le dit dans les deux cas — script absent, **ou binaire absent** (projet
npm/yarn/bun) — mais il ne peut alors plus rien prouver, et `tdd-require-red.sh`
refusera toute création de module, faute de rouge constaté. C'est voulu : mieux
vaut un blocage bruyant qu'un TDD qui se croit actif. Le seul piège serait un
blocage **silencieux** : si tu vois des refus de création sans jamais voir de
verdict `RED confirmed`, c'est `RUN_TESTS` qu'il faut regarder en premier.

**Le `include`/`exclude` de Vitest n'est pas optionnel**, lui. Le glob par défaut
(`**/*.{test,spec}.?(c|m)[jt]s?(x)`) ramasse les specs Playwright de `e2e/` et,
si tu as l'addon Supabase, les tests Deno de `supabase/functions/` — deux runners
qui ne sont pas vitest. `pnpm test:run` échoue alors à la collecte, et le gate de
`/loop:ship` part rouge sur du code intact. Le bloc est dans
`.claude/skills/templates/tooling-config.md`, section `vite.config.ts` (le bloc
`test` y est une clef de `vite.config.ts` — jamais un `vitest.config.ts` séparé,
qui remplacerait la config au lieu de la fusionner).

Le seuil de couverture (`pnpm test:coverage`) est optionnel mais recommandé, et
il a **sa propre dépendance** : `@vitest/coverage-v8`, qui ne vient pas avec le
core de Vitest. Sans elle la commande meurt avant la collecte — raison pour
laquelle `ci.yml` lance `test:run` et `test:coverage` en **deux steps** : le rôle
obligatoire « tests run-once » ne doit pas tomber avec un provider optionnel. Les
seuils sont dans `.claude/rules/05-testing.md` (« The three things that check
the suite itself »), le bloc de config dans
`.claude/skills/templates/tooling-config.md`. Attention à une asymétrie qui coûte
cher : le `include` de couverture doit couvrir **exactement** ce que les hooks
gèlent, les deux orthographes de chaque mot de couche (`x.utils.ts` **et**
`utils.ts` nu). Un fichier gelé hors du plancher est le pire des deux mondes.

**Les dépendances sans lesquelles aucun test ne démarre**, avant tout le reste —
les trois premières pour lancer la suite, la quatrième pour le plancher :

```bash
pnpm add -D vitest jsdom @testing-library/jest-dom @vitest/coverage-v8
```

`jsdom` est l'`environment` de la clef `test` de `vite.config.ts` — sans lui, le premier
`render()` meurt sur `document is not defined`, et le message ne ressemble pas à
un problème de config. `@testing-library/jest-dom` enregistre `toBeDisabled`,
`toHaveTextContent` et `toBeInTheDocument` : sans lui, les exemples de
`patterns/tests.md` échouent sur « n'est pas une fonction », sur un test
parfaitement correct. Les deux se câblent dans le même bloc :
`.claude/skills/templates/tooling-config.md`, section `vite.config.ts`
(clef `test` : `environment` + `setupFiles`), et le fichier de setup lui-même est déclaré une
seule fois, dans `templates/fixtures.md`.

Ajoute `jest-axe` (`pnpm add -D jest-axe @types/jest-axe`) si tu veux les tests
d'accessibilité de `patterns/a11y.md` — optionnel, contrairement aux trois
ci-dessus.

**Le gate lint, et il ne démarre pas tout seul non plus.** `pnpm lint
--max-warnings=0` est un gate de `/loop:ship` : sur ESLint 10 le parser par défaut
(espree) ne lit pas une annotation de type, donc sans `typescript-eslint` ce
n'est pas une dégradation, c'est un `Parsing error` qui fait tomber le gate au
premier `.ts`.

```bash
pnpm add -D eslint typescript-eslint @eslint/js   # le PARSER — sans lui, pas de gate du tout
pnpm add -D eslint-plugin-react-hooks   # les diagnostics du compilateur React
pnpm add -D @vitest/eslint-plugin       # pas `eslint-plugin-vitest`, c'est l'ancien
pnpm add -D eslint-plugin-jsx-a11y      # l'a11y devient un échec de build, pas un commentaire de review
```

Le bloc `eslint.config.js` est dans
`.claude/skills/templates/tooling-config.md` (la liste des règles et le pourquoi
restent dans `01-stack.md`, « The lint on the tests »). Sans lui,
`expect-expect` (un test sans aucune assertion),
`it.only` et `it.skip` ne bloquent rien — et ce sont exactement les trois choses
qu'un agent pressé de finir produit.

Deux pièges dans ce bloc, et le second est silencieux : un objet de flat config
**sans clef `files` ne s'applique qu'aux fichiers déjà ciblés par un autre
objet**. Cibler seulement `**/*.tsx` et `**/*.test.ts{,x}` laisse `hooks.ts`,
`*.repository.ts`, `*.mapper.ts`, `*.utils.ts` et `src/lib/*.ts` lintés par
**rien** — `rules-of-hooks` et `exhaustive-deps` n'évaluent aucun d'eux, et rien
ne le dit. Le bloc du template porte un objet de base en
`**/*.{js,jsx,ts,tsx}` pour cette raison précise.

### Deux outils optionnels, dans cet ordre

**MSW**, dès que tu écris un `gateway.ts` qui construit une requête (filtre, tri,
pagination, count). Sans lui, la seule option est un faux client chaîné qui
récite le gateway au lieu de le tester — et c'est pour ça que cette couche était
« as needed » jusqu'ici.

```bash
pnpm add -D msw                # tests de gateway  → .claude/skills/patterns/msw.md
pnpm add -D @msw/playwright    # couche mock E2E   → skills/e2e-playwright/SKILL.md
```

Dépend directement du tableau du client de données (point 1) : MSW intercepte du
HTTP. Sur l'addon Supabase, **commence par le smoke test** de
`patterns/msw-supabase.md` — il existe un ticket ouvert où le SDK ne passe pas
par MSW, et dix minutes de vérification t'évitent vingt handlers inutiles.

**Stryker**, plus tard, et jamais en gate :

```bash
pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner
echo -e '.stryker-tmp/\nreports/' >> .gitignore
```

Config et mode d'emploi dans `.claude/commands/audit/mutation.md`. C'est la seule
chose qui vérifie que les tests gelés *contraignent* le code au lieu de
simplement l'exécuter. Le runner Vitest impose `threads: true` — vérifie ta
config Vitest avant, c'est la seule chose qui l'empêche de démarrer.

### 4 bis. `.github/workflows/` → le miroir serveur des mêmes scripts

**Pas de dépôt distant ? Cette section ne te concerne pas** : `--no-ci` (ou
*non* à la première question de l'installeur) n'installe aucun workflow, et les
six rôles de gate ne bougent pas d'un pouce — c'est `/loop:ship` qui les tient, avant
chaque commit, comme il l'a toujours fait. Le CI n'a jamais été qu'une seconde
copie, pour la seule chose que `/loop:ship` ne peut pas couvrir : une machine qui
n'est pas la tienne. Le jour où tu pousses, relance l'installeur avec
`--deploy=<cible>`.

Sinon, `install.sh` a déposé deux fichiers, et ils dépendent entièrement des
scripts que tu viens de déclarer en §4 — un nom de script différent chez toi et le CI casse
au premier push, pas plus tard.

- **`ci.yml`** part opérationnel : cinq des six rôles de gate (`typecheck`,
  `lint`, `test:coverage`, `audit`, `build`), tous exécutés même si l'un échoue
  pour voir l'ensemble des dégâts en un run. Rien à remplir **si** tes scripts
  portent les noms de `00-project.md`. Sinon, aligne les `run:` — et tu n'as pas
  à le vérifier à l'œil : `/kit:doctor` compare les deux (`ci-scripts`), parce
  que c'est la **troisième** copie de la même liste (la règle la déclare,
  `/loop:ship` l'appelle en local, le CI l'appelle sur le runner). La divergence est
  silencieuse et sort au pire moment : CI rouge sur `main`, pour un nom de
  script que personne n'a touché, sur un diff qui va bien.
  **Le premier mur d'un projet neuf est ailleurs** : `pnpm/action-setup` exige
  un champ `packageManager` dans `package.json` (ou un `version:` explicite
  dans le workflow). Sans lui l'action ne se rabat sur rien, elle échoue, et
  c'est le tout premier step du tout premier push. Le kit ne scaffolde pas de
  `package.json` : ce champ est à toi.

- **`deploy.yml`** est **assemblé** à l'installation : le squelette + l'étape
  `Publish` de la cible que tu as choisie (`--deploy=`, ou la question posée par
  l'installeur dans un terminal). Cinq cibles livrées — `netlify`, `vercel`,
  `pages`, `ssh`, `ghcr` — chacune portant dans le fichier la liste exacte des
  secrets et variables GitHub à créer, et sa permission supplémentaire si elle
  en exige une (Pages et GHCR seulement, jamais accordée « au cas où »).

  Sur **`none`** — le défaut hors terminal — l'étape `Publish` est un `exit 1`.
  Un CD non configuré qui « réussit » à ne rien déployer est le pire des trois
  états : badge vert, personne ne regarde, et la prod n'a jamais bougé. Ce
  placeholder est compté par `/kit:doctor` (`fill-markers`), qui ne scannait que
  du markdown avant.

  Changer d'avis : `./install.sh <projet> --deploy=<autre>` écrit un
  `deploy.yml.new` à côté, à fusionner.

Puis **`CLAUDE.md`, section `Environment`** : deux lignes, le local et la prod.
Pas de production pour l'instant → écris `none yet` et **supprime
`deploy.yml`**, plutôt que de le laisser en échec permanent. Elles ne
s'excluent pas : un projet se développe en local *et* peut avoir une prod, et
lire « local » comme « jamais déployé » est exactement ce qui laisse un repo sans
CD et sans endroit où l'écrire.

Le contrat — quel rôle tourne où, pourquoi aucun agent ne tourne en CI, ce que
le CD garantit — est dans `.claude/skills/templates/ci.md`. Les YAML en sont la
seule copie exécutée.

## 5. `.claude/rules/02-architecture.md` → section « Backend »

Laissée vide = projet front-only, et du code backend dans un diff devient
lui-même un finding. Sinon : structure des handlers, style, validation, forme des
erreurs. Les addons fournissent le bloc à coller — `addons/supabase/` pour les
edge functions, `addons/fastapi/` pour un service FastAPI (qui ajoute aussi
`07-backend.md`, les commandes `/backend:*` et trois hooks Python — câblés
automatiquement sur une install neuve, à fusionner depuis le `.new` sinon :
voir le README de l'addon, qui liste aussi les gates backend à ajouter dans
`/loop:ship` et `07-backend.md` à ajouter aux dimensions du `reviewer`).

## 6. `.claude/rules/06-database.md`

Provider, dossier de migrations, et surtout les **commandes d'inspection
read-only** : c'est ce qui permet à `/loop:research` de compter les lignes au lieu de
supposer ce que le schéma autorise.

## 7. `CLAUDE.md`

Environnement et non-négociables. La section Git ne fait plus que router vers
l'agent : la convention entière (style des messages, format des PR, protocole de
merge d'une track) vit dans `.claude/agents/github.md`, sa copie unique.

Ce qui la tient n'est pas le texte mais
`.claude/hooks/enforce-git-workflow.sh` : commit sur `main`/`master` **refusé**,
signature et trailer `Co-Authored-By` **refusés**, et `git push`, `gh pr`,
`gh issue`, tout commentaire et tout merge dans une branche protégée repassent
par ta validation. Si tes branches protégées ne s'appellent pas `main`/`master`,
change `PROTECTED_BRANCHES` en tête du hook.

## 8. `.claude/rules/03-conventions.md` → les deux langues

Une langue pour les humains qui utilisent le produit, une pour la trace machine.
Le kit part sur user FR / logs EN. Tout le reste y fait référence.

## 9. `.claude/skills/patterns/feedback.md` et `guards.md`

Remplace les noms de composants et de helpers par ceux du projet. Un agent qui ne
trouve pas `<State>` en invente un — et c'est un composant de plus à maintenir,
né d'un fichier périmé.

## 10. `.claude/skills/e2e-playwright/SKILL.md` → « Which backend does the suite hit? »

La section la plus dangereuse à laisser vide : elle décide si un agent a le droit
de **muter des données**. Trois cas, une règle chacun :

| Cas                                      | Règle pour l'agent                                                    |
| ---------------------------------------- | --------------------------------------------------------------------- |
| Stack locale jetable, reset à chaque run | mutation autorisée, chaque spec sème et nettoie ses données           |
| Projet de test partagé et seedé          | mutation sur les données que la suite possède, rien d'autre           |
| Le vrai projet, partiellement mocké      | **lecture seule**, et la liste des actions à effet externe interdites |

Dans le doute, tu es dans le troisième cas.

## 11. `.claude/rules/09-icons.md`

Liste d'interdits maison (étoile, fusée, éclair), doublée par le hook
`no-forbidden-icons.sh`. À garder, modifier ou supprimer — mais les deux
ensemble, jamais l'un sans l'autre.

## 12. `.claude/guides/10-worktrees.md`

> `.claude/guides/` n'est **pas** chargé au démarrage — contrairement à
> `.claude/rules/`, dont tout le contenu arrive dans le contexte, importé ou non
> dans `CLAUDE.md`. Les fichiers de `guides/` portent le rationnel des règles et
> les règles qu'on lit à la demande ; ils se citent par chemin. Adapter un guide
> ne change rien au coût d'une session.

Utile seulement si tu mènes plusieurs features de front. Quatre choses à vérifier :

- `.claude/worktrees/` est dans le `.gitignore` du projet ;
- `worktree.baseRef` dans `.claude/settings.json` : le kit livre `head` (dépôt
  local, pas d'`origin` d'où brancher). Repo d'équipe avec un remote → `fresh` ;
- la branche de base est bien `main` (sinon corrige-la dans la règle et dans
  l'agent `github`) ;
- la liste des **fondations partagées** correspond à ton repo — la règle liste
  `src/lib`, `shared/`, le router, les providers, le lockfile, les migrations.
  Ajoute les tiennes (dossier infra, thème, i18n) : c'est cette liste qui décide
  ce qui ne forke jamais.

Si tu ne travailles jamais sur deux features en parallèle, la règle est inerte —
la garder ne coûte rien, elle ne déclenche que sur ≥ 2 tracks.

## 13. L'étage 0 de `/loop:review` → un navigateur, ou l'aveu

Le seul étage de toute la boucle qui **regarde** l'écran. Il a besoin de deux
choses sur la machine : de quoi lancer l'app (la skill `run`, donc les scripts du
point 4) et de quoi piloter un navigateur (`claude-in-chrome`, ou la skill
`e2e-playwright` si tu préfères prouver au spec plutôt qu'à l'œil).

Ce n'est pas un `FILL` et rien ne le vérifie au démarrage : c'est une capacité de
poste, pas un fichier. Si elle manque, la règle est dans `commands/review.md` —
la review le **déclare comme un trou du gate**, pas comme un skip, et les
critères d'acceptation qui supposaient qu'on voie l'écran ressortent en « non
observés ». Un contraste illisible, un débordement à 1280px et un état vide cassé
passent tous les autres gates sans faire un bruit.

---

## Vérifier que le câblage tient

Un hook qui refuse doit imprimer un JSON `permissionDecision: deny` ; un hook qui
autorise n'imprime **rien**.

```bash
H=.claude/hooks/enforce-architecture.py

# DENY — import cross-feature
echo '{"tool_input":{"file_path":"src/features/a/x.ts","content":"import {b} from \"@/features/b\";"}}' | python3 $H

# DENY — code partagé qui dépend d'une feature (les 6 entrées de SHARED_DIRS)
echo '{"tool_input":{"file_path":"src/components/ui/Nav.tsx","content":"import {u} from \"@/features/auth/hooks/hooks\";"}}' | python3 $H
echo '{"tool_input":{"file_path":"src/stores/theme.ts","content":"import {u} from \"@/features/auth/types/types\";"}}' | python3 $H
echo '{"tool_input":{"file_path":"src/config/nav.ts","content":"import {u} from \"@/features/auth/types/types\";"}}' | python3 $H

# DENY — client hors couche data
echo '{"tool_input":{"file_path":"src/features/a/hooks/hooks.ts","content":"import {client} from \"@/lib/client\";"}}' | python3 $H

# ALLOW (silence) — gateway, et composition root
echo '{"tool_input":{"file_path":"src/features/a/services/a.gateway.ts","content":"import {client} from \"@/lib/client\";"}}' | python3 $H
echo '{"tool_input":{"file_path":"src/routes/__root.tsx","content":"import {client} from \"@/lib/client\";"}}' | python3 $H

# DENY — any, y compris dans un argument générique
echo '{"tool_input":{"file_path":"src/a.ts","content":"const m: Record<string, any> = {};"}}' | bash .claude/hooks/no-any-type.sh

# protect-files distingue lecture et écriture : un secret est refusé dans les
# deux sens, un lock file seulement en écriture.
H=.claude/hooks/protect-files.sh
echo '{"tool_name":"Read","tool_input":{"file_path":".env.e2e"}}'      | bash $H   # DENY
echo '{"tool_name":"Read","tool_input":{"file_path":"pnpm-lock.yaml"}}' | bash $H  # silence
echo '{"tool_name":"Write","tool_input":{"file_path":"pnpm-lock.yaml"}}' | bash $H # DENY

# … et il couvre les trois portes du même fichier, pas seulement Read. Grep et
# Glob ne passent pas de `file_path` : ils nomment leur cible avec `path`,
# `glob`, `pattern`. Un secret bloqué en lecture et ouvert à la recherche n'est
# pas bloqué.
echo '{"tool_name":"Grep","tool_input":{"pattern":".","path":".env","output_mode":"content"}}' | bash $H  # DENY
echo '{"tool_name":"Grep","tool_input":{"pattern":"KEY","glob":"*.key"}}'                      | bash $H  # DENY
echo '{"tool_name":"Glob","tool_input":{"pattern":"**/.env*"}}'                                | bash $H  # DENY
echo '{"tool_name":"Grep","tool_input":{"pattern":"useQuery","path":"src","glob":"*.ts"}}'     | bash $H  # silence

# Le cycle TDD n'est fermé côté shell que si les DEUX langages le sont. Les six
# hooks TDD (trois TS, trois Python) sont tous sur Write|Edit : une redirection
# les contourne tous. Si tu n'as pas l'addon FastAPI, les deux dernières lignes
# passent — c'est normal, ces chemins n'existent pas chez toi.
H=.claude/hooks/prevent-destructive-commands.sh
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > features/a/a.utils.test.tsx"}}' | bash $H  # DENY
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > app/services/project.py"}}'     | bash $H  # DENY
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > app/api/routes.py"}}'           | bash $H  # silence

# DENY — créer un module test-first sans test vu échouer
echo '{"tool_input":{"file_path":"src/features/a/services/a.repository.ts"}}' | bash .claude/hooks/tdd-require-red.sh

# DENY — affaiblir une assertion dans un test gelé (le fichier doit exister)
echo '{"tool_input":{"file_path":"src/features/a/services/a.repository.test.ts","old_string":"expect(r.success).toBe(true);","new_string":"expect(r.success).toBeTruthy();"}}' | bash .claude/hooks/tdd-freeze-tests.sh

# plus aucun marqueur non traité
grep -rnE "FILL|CONFIGURE" .claude/ CLAUDE.md docs/
```

Un hook ne se teste pas comme les autres : **l'écriture d'un `.ts` depuis le
shell** (`prevent-destructive-commands.sh`). Lui envoyer son propre motif est
impossible — la commande de test contient le motif, donc c'est elle qui se fait
refuser. Ce refus **est** le test. Sur une couche test-first ou un fichier de
test c'est un `deny`, sur n'importe quel autre `.ts` c'est un `ask` (la génération
de types passe, mais par toi).

Le trio TDD se vérifie surtout **en marche** : écris un
`x.repository.test.ts`, regarde `tdd-prove-red` annoncer `RED confirmed`, puis
crée `x.repository.ts` — il doit passer. Refais-le sans le test : la création
doit être refusée. Si `tdd-prove-red` répond « could not run the test runner »,
c'est `RUN_TESTS` qui ne correspond pas à ton script (point 4).

Puis un tour à blanc : `/loop:spec une petite feature` doit produire
`docs/specs/<slug>.md` et s'arrêter là.
