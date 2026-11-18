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

## 2. `.claude/project.json` → `data_client` (`module`, `own_path`, `composition_roots`, `shared_dirs`)

Toutes les valeurs de projet appliquées par les hooks vivent dans
`.claude/project.json`, lu par un seul lecteur (`project_config.py`). **Aucun hook
ne s'édite** : `install.sh` crée ou met à niveau ce fichier (il reprend les
valeurs d'un ancien hook modifié à la main), `/kit:init` le remplit. Dans un projet
installé, ce fichier est du code du kit, refusé à l'agent (§14) : `/kit:init` écrit
`.claude/project.proposed.json`, et tu l'appliques toi-même, depuis ton terminal,
avec `bash .claude/scripts/kit-apply.sh` (il valide, sauvegarde, puis remplace).
Chaque « change … dans `.claude/project.json` » de ce document passe par là. Un fichier
invalide ou absent fait tourner les hooks sur les défauts du kit, en mode
dégradé : un refus reste un refus, mais un passage devient une demande, avec la
réparation dans le message.

`data_client.module` doit correspondre au point 1, sinon le hook garde une porte
qui n'existe pas.

`data_client.composition_roots` liste les fichiers qui **créent** l'instance du client et
l'injectent dans le contexte routeur/provider — par défaut `main.tsx` et
`routes/__root.tsx`. Ce sont les seuls, hors couche data, autorisés à l'importer.
Si ton point d'entrée est ailleurs, corrige la liste ici **et** le tableau
« composition root » de `02-architecture.md` : c'est le même contrat écrit deux
fois, une fois pour la machine, une fois pour l'agent.

`data_client.shared_dirs` est la troisième, et elle a **trois** copies : la liste de
`.claude/project.json`, les deux listes d'import de `02-architecture.md` et la
ligne « code partagé » de `CLAUDE.md`. Le kit livre six entrées —
`components/ hooks/ lib/ types/ stores/ config/`. `providers/` et `routes/` en
sont volontairement absents : ce sont des câblages, ils ont le droit de connaître
les features qu'ils composent. Ajoute un répertoire feuille à ton arborescence
(`src/constants/`, `src/utils/`…) et il faut le mettre à ces endroits. Le reviewer
`correctness` lit la liste directement dans `.claude/project.json` (il ne la
recopie plus), ce qui compte, parce que le hook n'inspecte que le **delta inséré**
d'un Edit : le reviewer est le seul filet pour un import déjà présent ailleurs.

Les templates du kit ne sont jamais réécrits pour ton client : ils disent de lire
`data_client.module` dans `.claude/project.json` (`install.sh --supabase` n'y touche
plus non plus). `/kit:doctor` compare la liste à la case « Forbidden » de
`02-architecture.md` et à `CLAUDE.md` (`check_shared_dirs`). La liste
« Allowed from anywhere » de `02-architecture.md` reste **manuelle** : elle est
énumérative et non miroir de la liste (`providers/` y figure, pas dans
`shared_dirs`). La synchronisation reste à ta charge, mais l'oubli ne passe plus
en silence.

### 2 bis. `env_template_suffixes` → les suffixes `.env` sans secret

Une seule liste dans `.claude/project.json` (le kit livre `example`, `sample`,
`template`) : `protect-files.sh`, `auto-approve-config.sh`,
`prevent-destructive-commands.sh` et `enforce-git-workflow.sh` la lisent tous,
donc les outils et le shell protègent toujours le même ensemble. Si ton repo
utilise une autre convention (`.env.dist`, `.env.tpl`), change la liste **et** les
entrées `Read(!.env.<suffixe>)` de `settings.json`, que `/kit:init` écrit avec.
Les mots qui nomment un vrai secret (`local`, `production`, `development`, `prod`,
`dev`, `staging`, `test`) sont refusés : le fichier devient invalide et les hooks
passent en mode dégradé.

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

La commande run-once que `tdd-prove-red.sh` lance sur un fichier de test est
`test_command` dans `.claude/project.json` : si la tienne n'est pas `pnpm test:run`,
change-la là aussi, par la proposition du §2 (de même `formatter` et `linter` pour
les hooks d'après-save).
Le hook le dit dans les deux cas — script absent, **ou binaire absent** (projet
npm/yarn/bun) — mais il ne peut alors plus rien prouver, et `tdd-require-red.sh`
refusera toute création de module, faute de rouge constaté. C'est voulu : mieux
vaut un blocage bruyant qu'un TDD qui se croit actif. Le seul piège serait un
blocage **silencieux** : si tu vois des refus de création sans jamais voir de
verdict `RED confirmed`, c'est `test_command` qu'il faut regarder en premier.

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

Avec le CI, `install.sh` dépose aussi `.github/CODEOWNERS` (remplace `@OWNER` ; il couvre les hooks, `settings.json`, `project.json`, les workflows et lui-même), et les réglages du
dépôt qui rendent les gates bloquantes (ruleset sur `main`, check requis
`Gates`, environnement `production`) sont décrits dans
`.claude/skills/templates/ci.md`, « Repository settings ». Dans le dépôt du kit
lui-même, le check requis `kit` (`kit-ci.yml`) s'ajoute à `Gates` : il n'existe
que là, `kit-ci.yml` n'étant jamais installé chez toi, donc ne l'exige jamais
dans ton projet.

Un pre-push local est optionnel : `--lefthook` (ou *oui* à la question posée
dans un terminal) dépose `lefthook.yml`, qui relance typecheck, lint et
`test:run` avant chaque push ; active-le avec
`pnpm add -D lefthook && pnpm exec lefthook install`.

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
  La cible SSH demande aussi `DEPLOY_KNOWN_HOSTS`, vérifié hors bande, et un
  `DEPLOY_HOST` sur une IP statique ou un nom stable : l'entrée `known_hosts`
  est liée à cette adresse.

  Sur **`none`** — le défaut hors terminal — l'étape `Publish` est un `exit 1`.
  Un CD non configuré qui « réussit » à ne rien déployer est le pire des trois
  états : badge vert, personne ne regarde, et la prod n'a jamais bougé. Ce
  placeholder est compté par `/kit:doctor` (`fill-markers`), qui ne scannait que
  du markdown avant.

  Changer d'avis : `./install.sh <projet> --deploy=<autre>` écrit un
  `deploy.yml.new` à côté, à fusionner.

  dependabot arrive avec le CI et surveille les actions GitHub comme les
  dépendances npm.

  Une cible déjà installée garde son ancien `deploy.yml` : elle doit fusionner le
  `deploy.yml.new` pour recevoir ces garanties. Relance l'installeur avec son
  propre `--deploy=<cible>` : hors terminal le défaut est `none`, et le
  `deploy.yml.new` porterait alors un `exit 1`. Sur SSH, cette fusion rend
  `DEPLOY_KNOWN_HOSTS` obligatoire.

  dependabot ne lit pas les lignes `pnpm` des `run:` : les versions des CLI
  (`netlify-cli`, `vercel`) se montent à la main. Les versions majeures npm sont
  exclues exprès (`01-stack.md` : changer de version est une décision).

  Le déclenchement manuel exécute le fichier de la ref choisie : une branche peut
  réécrire son propre `if:` et le step Resolve. Là où le déploiement exige un
  secret d'environnement, l'environment est la barrière : règle « Deployment
  branches and tags » sur Selected avec la branche par défaut (pas « Protected
  branches only », qui autorise toutes les branches quand aucune règle de
  protection n'existe), et garde les secrets de déploiement en secrets
  d’environnement, les copies au niveau du dépôt supprimées. `ghcr` n'a aucun
  secret et se connecte avec `GITHUB_TOKEN` : un workflow de branche avec
  `packages: write` peut pousser quelle que soit la règle, la confiance repose
  là sur qui a l'accès en écriture. Pour `pages`, ce point n'est pas tranché.
  Limites de plan : les required reviewers existent sur GitHub Free, Pro et Team pour
  les dépôts publics seulement ; les règles de branche et les secrets
  d’environnement existent aussi sur les dépôts privés Pro et Team ; sur un dépôt
  privé Free, il n'y a ni l'un ni l'autre.

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
signature et trailer `Co-Authored-By` **refusés** (dans un commit comme dans un
corps, un titre ou un `--body-file` envoyé par `gh`), et `git push`, `gh pr`,
`gh issue`, tout commentaire et tout merge dans une branche protégée repassent
par ta validation, quels que soient les options globales, le `-C` ou l'alias de
l'appel git. Si tes branches protégées ne s'appellent pas `main`/`master`,
change `protected_branches` dans `.claude/project.json` par la proposition du §2
(globs admis, ex. `release/*`).

## 8. `.claude/rules/03-conventions.md` → les deux langues

Une langue pour les humains qui utilisent le produit, une pour la trace machine.
Le kit part sur user FR / logs EN. Tout le reste y fait référence.

## 9. `.claude/overlays/skills/patterns/feedback.md` et `guards.md`

Un prompt du kit n'est jamais édité dans un projet installé : tes valeurs vivent
dans `.claude/overlays/<chemin du prompt sous .claude/>`, une section `## <slot>`
par valeur. Ici : `components` et `strings` (feedback), `names` (guards) — les noms
de composants et de helpers du projet. Un agent qui ne trouve pas `<State>` en
invente un — et c'est un composant de plus à maintenir, né d'un fichier périmé.

## 10. `.claude/overlays/skills/e2e-playwright/SKILL.md` → `backend-case`

Sections `drivers`, `harness` et `backend-case` de cet overlay. `backend-case` est la
section la plus dangereuse à laisser vide : elle décide si un agent a le droit
de **muter des données** (absente, l'agent s'arrête et demande). Trois cas, une règle chacun :

| Cas                                      | Règle pour l'agent                                                    |
| ---------------------------------------- | --------------------------------------------------------------------- |
| Stack locale jetable, reset à chaque run | mutation autorisée, chaque spec sème et nettoie ses données           |
| Projet de test partagé et seedé          | mutation sur les données que la suite possède, rien d'autre           |
| Le vrai projet, partiellement mocké      | **lecture seule**, et la liste des actions à effet externe interdites |

Dans le doute, tu es dans le troisième cas.

## 11. `.claude/rules/09-icons.md`

Liste d'interdits maison (étoile, fusée, éclair), doublée par `forbidden_icons`
dans `.claude/project.json`, que lit `no-forbidden-icons.sh`. À garder, modifier
ou vider — mais les deux ensemble, jamais l'un sans l'autre.

## 12. `.claude/overlays/guides/10-worktrees.md` → `foundations`

> `.claude/guides/` n'est **pas** chargé au démarrage — contrairement à
> `.claude/rules/`, dont tout le contenu arrive dans le contexte, importé ou non
> dans `CLAUDE.md`. Les fichiers de `guides/` portent le rationnel des règles et
> les règles qu'on lit à la demande ; ils se citent par chemin. Ce guide est du
> code du kit : tes ajouts vont dans son overlay, jamais dans le guide.

Utile seulement si tu mènes plusieurs features de front. Quatre choses à vérifier :

- `.claude/worktrees/` est dans le `.gitignore` du projet ;
- `worktree.baseRef` dans `.claude/settings.json` : le kit livre `head` (dépôt
  local, pas d'`origin` d'où brancher). Repo d'équipe avec un remote → `fresh` ;
- la branche de base est bien une des `protected_branches` de `.claude/project.json`
  (sinon corrige-la dans la proposition `.claude/project.proposed.json`, et les
  préfixes de branche dans la section `branches` de l'overlay de l'agent `github`) ;
- la liste des **fondations partagées** correspond à ton repo — la règle liste
  `src/lib`, `shared/`, le router, les providers, le lockfile, les migrations.
  Ajoute les tiennes (dossier infra, thème, i18n) dans la section `foundations` de
  l'overlay : c'est cette liste qui décide ce qui ne forke jamais.

Si tu ne travailles jamais sur deux features en parallèle, la règle est inerte —
la garder ne coûte rien, elle ne déclenche que sur ≥ 2 tracks.

## 13. L'étage 0 de `/loop:review` → un navigateur, ou l'aveu

Le seul étage de toute la boucle qui **regarde** l'écran. Il a besoin de deux
choses sur la machine : de quoi lancer l'app (la skill `run`, donc les scripts du
point 4) et de quoi piloter un navigateur (`claude-in-chrome`, ou la skill
`e2e-playwright` si tu préfères prouver au spec plutôt qu'à l'œil).

Ce n'est pas un marqueur à remplir et rien ne le vérifie au démarrage : c'est une
capacité de poste, rien à écrire dans `.claude/overlays/` ni dans
`.claude/project.json`. Si elle manque, la règle est dans la commande
`/loop:review` — la review le **déclare comme un trou du gate**, pas comme un skip, et les
critères d'acceptation qui supposaient qu'on voie l'écran ressortent en « non
observés ». Un contraste illisible, un débordement à 1280px et un état vide cassé
passent tous les autres gates sans faire un bruit.

### Impeccable (optionnel, UI uniquement)

L'étage 0 et l'agent `designer` utilisent [Impeccable](https://github.com/pbakaus/impeccable)
quand il est installé : détecteur déterministe (`pnpm dlx impeccable detect`), puis
`/impeccable critique` et `audit`. Le kit ne le fournit pas : copie le skill
seul dans le dossier `skills/` de ton `.claude/`, sans ses hooks, et ne lance pas
`pnpm dlx impeccable install` (il écrit dans `settings.local.json`). Le détecteur
demande **Node 22.18 ou plus**. Absent ou en échec, la review le déclare comme un
trou du gate, jamais comme « propre ».

`PRODUCT.md` et `DESIGN.md` à la racine sont des **pointeurs** vers
`docs/product/brief.md` et `docs/design-system.md` : ne lance jamais
`impeccable init` dessus. S'il les rejette, le repli est de les générer depuis le
brief, dans un autre passage.

### Motion (optionnel, UI uniquement)

Le kit ne fournit aucune bibliothèque : ton app installe ce dont elle a besoin.
Les conventions sont dans les patterns `motion` (défaut : CSS ou Motion) et `gsap`
(seulement si le spec déclare `Motion: gsap - <raison>`), du dossier `patterns/` des
skills du kit. Versions et licences : `docs/research-cache/motion.md` et `gsap.md`,
à revérifier au-delà de 30 jours. Limite à connaître : l'étage 0 ne juge pas le
mouvement, et Impeccable n'attrape que des motifs de code connus.

---

### Context7 (optionnel, priorité basse)

`doc-researcher` pèse peu (environ 0,3 % du coût mesuré). Son `tools:` liste déjà
les outils de Context7 pour un serveur enregistré sous le nom `context7`
(`claude mcp add … context7 …`, cf. `docs/research-cache/context7.md`) : rien à
faire si c'est ton cas. Un outil listé qu'aucun serveur ne fournit est ignoré par
Claude Code, donc sans Context7 l'agent saute cette étape ; rien d'autre ne change.
Enregistré sous un autre nom (vérifie avec `/mcp`) : l'agent ne l'atteint pas ;
c'est du code du kit, refusé dans un projet installé, et l'overlay ne peut pas
atteindre son frontmatter — réenregistre le serveur sous `context7`.

## 14. Chemins gardés

Les garde-fous du kit reposent sur des fichiers que l'agent pourrait lui-même
réécrire : les hooks, leurs échappatoires, les marqueurs RED, la configuration
des gates. Leur liste est unique, dans `.claude/hooks/hook-guarded.sh`, et tout
hook qui en a besoin appelle `cwk_is_guarded` au lieu de la recopier :

- `.claude/hooks/*` (fixtures et `hook-lib.sh` compris), `.claude/scripts/*`,
  `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`,
  `.claude/project.json` ;
- sous chaque **app root** déclaré dans `.claude/project.json` (`app_roots`, par
  exemple `frontend`), les mêmes fichiers de config que la racine : `frontend/vite.config.*`,
  `frontend/package.json`, `frontend/tsconfig*.json`… Une option `-p`/`--root`/`--config`
  qui vise un app root déclaré passe alors sans demander (`tsc -p .` depuis `frontend/`).
  Une redirection shell (`>`, `>>`) vers un `.ts`/`.tsx`/`.py` est **refusée** (« Use
  Write/Edit »), sauf depuis un générateur listé dans `codegen_commands` (par exemple
  `["supabase","gen","types"]`), qui demande. Un `project.json` absent ou invalide ne
  déclare rien. L'absent est normal : le doctor répond `ok`. Seul un fichier invalide,
  ou un app root déclaré qui n'existe pas, est signalé par `/kit:doctor`
  (`project-config`) ; `/kit:init` le remplit ;
- `vitest.config.*`, `eslint.config.*`, `vite.config.*` (le plancher de
  couverture), `playwright.config.*`, `package.json` (les scripts des gates),
  `tsconfig*.json`, `.github/workflows/*` ;
- les lanceurs à la racine (`install.sh`, `workflow.py`, `workflow.sh`,
  `codex-handoff.sh`) et `addons/*` (les suites du kit les exécutent) ;
- les dossiers qui les contiennent (`.claude`, `.github`, la racine).

Un `Write` ou un `Edit` sur l'un d'eux **demande ton accord**, depuis l'arbre
principal comme depuis `.claude/worktrees/<x>/`. `.claude/.tdd-red/` est
**refusé** : seul `tdd-prove-red.sh` y écrit, et un marqueur écrit à la main
ferait passer un module sans RED observé.

Il en va de même pour le shell : une écriture sur un chemin gardé, quel que soit
le moyen (redirection, `cp`, `sed -i`, `find -exec`, un programme inline passé à un
interpréteur), demande ton accord. Sur `.claude/.tdd-red/`, elle est refusée. Un
`rm -r` ou un `mv` sous un dossier protégé (`src/`, `.claude/`…) demande aussi ton
accord, et tout autre `rm -r` dans le projet aussi : `acceptEdits` approuve `rm`
seul, le hook remet l'invite. La racine d'un dossier protégé reste refusée.

Conséquence voulue :
dans le dépôt du kit, chaque écriture d'un hook, d'un script ou des settings demande ton accord.
Dans ton projet, c'est la même chose pour `package.json` ou `vite.config.ts` :
approuve si le changement est voulu.

**Le code du kit, refusé dans un projet installé.** Un projet où `install.sh` a
écrit `.claude/INSTALL_PROFILE` refuse, sans demander, toute écriture du code du
kit : `.claude/hooks/*`, `.claude/scripts/*`, `workflow.py`, `workflow.sh`,
`codex-handoff.sh`, `install.sh`, `addons/`, `.claude/project.json`,
`.claude/project.snapshot.json`, le tampon lui-même, `.claude/kit-manifest` et les
**prompts du kit** : les fichiers des dossiers `agents/`, `commands/`, `skills/` et
`guides/` de `.claude/` que liste `.claude/kit-manifest` (écrit par `install.sh`) ;
(par exemple `.claude/skills/patterns/motion.md`, lu comme tel : jamais édité sur place) ;
un prompt à toi, absent du manifeste, reste modifiable. Les valeurs et règles locales
d'un prompt vont dans `.claude/overlays/<son chemin sous .claude/>`, que la ligne
« Kit prompts » de `CLAUDE.md` demande de lire avant de suivre le prompt. Le refus vaut pour `Write`/`Edit`
(chemin lu tel quel ou après résolution des liens), pour le shell (écriture,
suppression, déplacement, copie dans un dossier, y compris le dossier parent) et
pour git (un `checkout`, `restore`, `reset`, `stash`, `apply`, `merge`, `pull`…
qui changerait ces fichiers ; ce que git ne peut pas lire demande ton accord).
Le message dit où le changer : `kit code changes in the LoopKit repo, then
`install.sh``. Tes valeurs passent par `.claude/project.proposed.json` et
`bash .claude/scripts/kit-apply.sh` (§2), que l'agent ne lance jamais. Dans le
dépôt du kit, rien ne change : ces chemins demandent ton accord, comme ci-dessus.

Si `hook-guarded.sh` disparaît, les cinq hooks de garde refusent tout (exit 2)
plutôt que de laisser passer ; rétablis-le depuis un terminal :
`git checkout -- .claude/hooks/hook-guarded.sh`.

Les sept branchements des hooks de garde (`protect-files.sh` ×3, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`, `tdd-require-red.sh`, `tdd-freeze-tests.sh`) portent `"onFailure": "block"` : un hook qui dépasse son timeout ou plante bloque l'appel au lieu de le laisser passer.
Mesuré sur Claude Code 2.1.316 ; une version plus ancienne est supposée ignorer la clé, ce n'est pas testé.

## 15. Permissions étroites (P1) et la mise à jour du code du kit

`.claude/settings.json` livre `permissions.defaultMode: "acceptEdits"` et cinq
autorisations exactes : `Bash(git add *)`, `Bash(git commit -m *)`,
`Bash(git switch -c *)`, `Bash(git branch --show-current)`,
`Bash(git worktree list)`. Pas de `git *`, `git push *`, `git commit *`,
`git switch *` ni `git branch *`. Ce qui rend ces formes sûres, c'est
`enforce-git-workflow.sh` : il refuse `git add -f`, un `git add` qui stagerait
un secret (`.env*`, `*.pem`, `*.key`, `credentials.*`) ou dont il ne peut pas
lire les chemins (avec `--no-dry-run`, par exemple). Un `git add` doit être
seul dans son appel, et seules des formes strictes passent sans invite, sur une
ligne : `git add [--] <chemins>`,
`git commit -m "<une ligne>"` ou entre apostrophes, et `git switch -c <branche>`.
`git -C <arbre> add …` et `git stage`, son synonyme, passent le hook aux mêmes règles mais aucune autorisation P1 ne les couvre : ils demandent ton accord. Un chemin s'écrit en ASCII sans
espace, n'est ni `.` ni un dossier et ne contient pas `..` ; un message ne contient
ni `$`, ni accent grave, ni `\`, ni son guillemet. Tout autre appel qui nomme `git`
et `add`, `stage`, `commit` ou `switch` demande ton accord, même sans danger
(`git diff src/commit.ts`), car le hook ne cherche plus à lire le shell : un `mv`,
`sed -i`, `rm` ou `cp` glissé dans l'appel changerait ce qui est stagé. Il
demande aussi ton accord sur `--amend`, `--no-verify`, `--all`, `--include`,
`--only`, `--patch`, `--interactive`, un commit avec un pathspec,
`--discard-changes`, `--force` et `--force-create`. Sans python3, sur une
commande illisible ou au-delà de 50 appels git, il lit les mots bruts, même
entre guillemets : il refuse tout `git add`/`git stage` et demande pour tout
commit, switch ou checkout (un message de commit qui cite `git add` est alors
refusé lui aussi).

**À la fusion.** `install.sh` fait l'union de `allow` (les tiennes restent, les
cinq s'ajoutent) et garde ton `defaultMode` s'il en a un : ta clé gagne toujours.

**Les secrets refusés nativement.** Le kit livre aussi un `permissions.deny` :
`Read(.env)`, `Read(.env.*)`, `Read(!.env.example)`, `Read(!.env.sample)`,
`Read(!.env.template)`, `Read(!.env.*.example)`, `Read(!.env.*.sample)`,
`Read(!.env.*.template)` (un modèle comme `.env.local.example` reste lisible),
`Read(*.pem)`, `Read(*.key)`, `Read(credentials.*)`, `Read(.credentials.*)`. L'ordre compte : une entrée `!` ne retire que des
entrées écrites avant elle, dans le même fichier. `install.sh` en fait l'union
dans l'ordre : tes entrées d'abord, puis celles du kit qui manquent, sans tri
(un tri mettrait les `!` en tête, où ils ne retirent rien). Mesuré le 2026-11-01 sur Claude Code 2.1.316 : l'outil Read et
`cat` sont refusés sur `.env` et `.env.local`, `.env.example` reste lisible.
Ce refus ne lie que les commandes que Claude Code reconnaît et les cibles de
redirection : un interpréteur qui ouvre le fichier lui-même, ou un `grep -r`
lancé depuis le dossier, n'est pas couvert. `prevent-destructive-commands.sh`
rattrape les formes connues (glob, contournement du wrapper de `grep`, `rg -uu`,
`printenv`), sans être un bac à sable. Le bac à sable de Claude Code
(`sandbox.enabled`, avec `bubblewrap` et `socat` sous Linux) couvrirait aussi
les sous-processus, mais le kit ne l'active pas : `autoAllowBashIfSandboxed`
vaut `true` par défaut et retire les invites des commandes Bash, et son effet
sur un `ask` de hook n'est pas mesuré. Active-le toi-même si tu en as besoin.

**La mise à jour du code du kit.** P1 sans les hooks qui le surveillent serait un
`acceptEdits` nu : c'est pourquoi `install.sh` remplace le code du kit
(`.claude/hooks/`, `.claude/scripts/`, `workflow.py`, `workflow.sh`,
`codex-handoff.sh`, et avec `--fastapi` les hooks de l'addon) par la version du kit,
dans le même run qui écrit P1. Les hooks sont donc toujours à jour, et P1 est
toujours appliqué. Chaque fichier qui diffère est d'abord sauvegardé, à son chemin,
dans `.claude/kit-backup/<heure UTC>/` (un dossier par run, ignoré par git) ;
l'installeur nomme ce dossier et les fichiers remplacés, ou dit
`kit code: up to date`. Tes modifications d'un hook y restent : refais-les dans le
dépôt du kit, puis relance `install.sh`. Supprime ces dossiers quand tu n'en as plus
besoin. Tout le reste (`CLAUDE.md`, les règles, les commandes, les docs) part
toujours en `.new` à fusionner. Les autorisations retirées sont retirées à chaque
installation. Le kit ne livre plus aucun joker d'arguments pour ces
runners : `Bash(pnpm build *)`, `Bash(pnpm test:run *)`,
`Bash(pnpm test:coverage *)`, `Bash(pnpm lint *)`, `Bash(pnpm typecheck *)`,
`Bash(pnpm vitest run *)`, `Bash(pnpm exec vitest run *)`,
`Bash(pnpm exec tsc --noEmit *)` et `Bash(pnpm exec playwright test *)`.
`install.sh` les retire de ton projet à chaque installation,
même si tu les avais ajoutés toi-même : le hook ne peut pas savoir quel
programme un nom de script lance (reporters à virgule, `-c` collé, globs,
`tsc -b` positionnel : revue 5). Les formes nues (`pnpm build`, `pnpm test:run`…)
et `Bash(pnpm audit *)` restent, donc les gates tournent sans invite ; un appel
avec arguments (`pnpm test:run <chemin>`, `pnpm lint --max-warnings=0`,
`pnpm exec playwright test …`) demande une confirmation.

Tes réglages ne sont pas dans les hooks : ils vivent dans `.claude/project.json`,
que l'installeur ne remplace jamais. Il le crée, ou le met à niveau, en lisant les
valeurs de tes hooks **avant** de les remplacer (un ancien hook modifié à la main),
et nomme chaque valeur qu'il n'a pas pu lire ; un élément illisible
d'`PROTECTED_DIRS` ou `PROTECTED_BRANCHES` est écarté seul, avec une note, et les
valeurs par défaut s'ajoutent. Sans valeur trouvée, la migration écrit les valeurs
par défaut et le dit. Les suites de développement du kit `test-install` et
`test-workflow-contracts` gardent leur autorisation dans le kit seul, jamais dans
une cible : une autorisation identique ajoutée par toi est retirée. Seuls ces
réglages du kit sont retirés ; tes autres autorisations et un `defaultMode` choisi
par toi restent. `install.sh` ne touche pas `.claude/settings.local.json` : une
approbation « don't ask again » qui y est enregistrée survit ; vide-la à la main si
besoin.

**Mesurer le gain.** Le temps mort des invites de permission sur une passe light
se lit dans le transcript de session (`docs/measuring-the-loop.md`) : l'écart
entre un `tool_use` et son `tool_result`, sur les appels qui ont demandé un
accord, additionné par passe. « Avant » vient d'un transcript de passe light
existant, « après » de la suivante.

## Vérifier que le câblage tient

Un hook qui refuse doit imprimer un JSON `permissionDecision: deny` ; un hook qui
autorise n'imprime **rien**.

```bash
H=.claude/hooks/enforce-architecture.py

# DENY — import cross-feature
echo '{"tool_input":{"file_path":"src/features/a/x.ts","content":"import {b} from \"@/features/b\";"}}' | python3 $H

# DENY — code partagé qui dépend d'une feature (les 6 entrées de shared_dirs)
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
export CLAUDE_PROJECT_DIR=$PWD   # sans projet, le garde ne classe aucune cible
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > features/a/a.utils.test.tsx"}}' | bash $H  # DENY
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > app/services/project.py"}}'     | bash $H  # DENY
echo '{"tool_name":"Bash","tool_input":{"command":"echo x > app/api/routes.py"}}'           | bash $H  # DENY (Use Write/Edit)

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
test c'est un `deny`, sur n'importe quel autre `.ts`/`.tsx`/`.py` c'est aussi un
`deny` (« Use Write/Edit ») ; seul un générateur listé dans `codegen_commands`
(la génération de types) passe, mais par un `ask` : par toi.

Le trio TDD se vérifie surtout **en marche** : écris un
`x.repository.test.ts`, regarde `tdd-prove-red` annoncer `RED confirmed`, puis
crée `x.repository.ts` — il doit passer. Refais-le sans le test : la création
doit être refusée. Si `tdd-prove-red` répond « could not run the test runner »,
c'est `test_command` qui ne correspond pas à ton script (point 4).

Puis un tour à blanc : `/loop:spec une petite feature` doit produire
`docs/specs/<slug>.md`, enchaîner la boucle et s'arrêter au premier gate pour te
demander le contrat (interface s'il y a un écran, sinon plan de tests).
