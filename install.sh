#!/usr/bin/env bash
#
# LoopKit — installe le kit dans un projet cible.
#
#   ./install.sh /chemin/vers/mon-projet [--supabase] [--fastapi]
#                                        [--no-ci]
#                                        [--deploy=none|netlify|vercel|pages|ssh|ghcr]
#
# --no-ci   n'installe AUCUN workflow GitHub. Pour un projet local sans depot
#           distant : les workflows n'y tourneraient jamais, et un deploy.yml
#           non rempli resterait un FILL que personne ne finira. Les gates, elles,
#           ne bougent pas — c'est /ship qui les tient, avec ou sans CI.
#
# --deploy  choisit la cible du CD. Omis dans un terminal, la question est posee ;
#           omis dans un script (pas de TTY), c'est `none` — le workflow echoue
#           alors volontairement tant que personne n'a choisi.
#
# Ne remplace jamais un fichier existant : il écrit `<fichier>.new` à côté et
# le signale à la fin. À toi de fusionner.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
shift || true
WITH_SUPABASE=false
WITH_FASTAPI=false
DEPLOY_TARGET=""
NO_CI=false

for arg in "$@"; do
    case "$arg" in
        --supabase) WITH_SUPABASE=true ;;
        --fastapi)  WITH_FASTAPI=true ;;
        --deploy=*) DEPLOY_TARGET="${arg#*=}" ;;
        --no-ci)    NO_CI=true ;;
        *) echo "erreur: option inconnue '$arg'." >&2; exit 1 ;;
    esac
done

# Les cibles disponibles SONT les fichiers de templates/github/publish/. Aucune
# liste en dur : en ajouter une, c'est deposer un fichier, et la question comme
# la validation le voient immediatement.
DEPLOY_DIR="$KIT_DIR/templates/github/publish"
# `none` en dernier, et jamais premier : `select` n'a pas de defaut, mais une
# liste alphabetique le poserait au milieu, ou il se choisit par accident.
mapfile -t DEPLOY_TARGETS < <(cd "$DEPLOY_DIR" && ls -1 *.yml | sed 's/\.yml$//' \
    | sort | grep -v '^none$'; echo none)

deploy_is_valid() {
    local t="$1" candidate
    for candidate in "${DEPLOY_TARGETS[@]}"; do
        [[ "$candidate" == "$t" ]] && return 0
    done
    return 1
}

if [[ -z "$TARGET" ]]; then
    echo "usage: ./install.sh /chemin/vers/mon-projet [--supabase] [--fastapi]" >&2
    exit 1
fi
if [[ ! -d "$TARGET" ]]; then
    echo "erreur: '$TARGET' n'est pas un dossier." >&2
    exit 1
fi

SKIPPED=()
INSTALLED=()

# copy_file <source> <destination>
copy_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" ]]; then
        cp "$src" "$dst.new"
        SKIPPED+=("$dst")
    else
        cp "$src" "$dst"
        INSTALLED+=("$dst")
    fi
}

# copy_override <source> <destination>
# L'addon remplace le fichier générique que CE run vient d'installer.
# Si le fichier préexistait dans le projet, on retombe sur le .new.
copy_override() {
    local src="$1" dst="$2" f
    for f in "${INSTALLED[@]:-}"; do
        if [[ "$f" == "$dst" ]]; then
            cp "$src" "$dst"
            return
        fi
    done
    copy_file "$src" "$dst"
}

# install_deploy <cible>
# Assemble deploy.yml : le squelette + jusqu'a quatre fragments de la cible.
# Un seul squelette, un fichier par fragment : les quatre proprietes du CD
# n'existent qu'a un endroit et ne peuvent pas diverger d'une cible a l'autre.
#
#   <cible>.yml    le step Publish            OBLIGATOIRE
#   <cible>.perms  une permission en plus     optionnel (pages, ghcr)
#   <cible>.environment  le bloc `environment:` entier  optionnel (pages)
#                        PAS `.env` : ce suffixe est celui des fichiers de
#                        secrets, et protect-files.sh refuse de les lire.
#
# CONTRAT : chaque fragment porte SA PROPRE indentation, awk les recopie tels
# quels. C'etait vrai de trois fragments sur quatre et faux de `.environment`,
# a qui awk ajoutait six espaces — un fragment ecrit en regardant son voisin
# indente produisait alors un bloc a deux niveaux, YAML invalide, visible
# seulement chez GitHub. Une seule regle, pour les quatre.
#   <cible>.spa    le fallback SPA            optionnel (ssh/ghcr : cote nginx)
#
# Un fragment absent n'est pas une erreur : le marqueur disparait, sauf pour
# l'environment qui retombe sur `production`.
install_deploy() {
    local target="$1"
    local skeleton="$KIT_DIR/templates/github/deploy.yml"
    local step="$DEPLOY_DIR/$target.yml"
    local perms="$DEPLOY_DIR/$target.perms"   # optionnels : la plupart des cibles
    local envf="$DEPLOY_DIR/$target.environment"  # n'en ont aucun
    local spa="$DEPLOY_DIR/$target.spa"
    local out

    # awk lit les snippets avec `getline < fichier`, qui retourne -1 sur un
    # fichier absent SANS erreur et sans executer le corps de boucle. Le
    # marqueur serait alors consomme et remplace par rien : un deploy.yml sans
    # step Publish, qui parse, qui tourne, et qui reussit en ne deployant rien.
    # Exactement l'etat que `none.yml` existe pour rendre impossible. On refuse
    # ici, bruyamment, plutot que de faire confiance a awk.
    if [[ -z "$target" ]]; then
        echo "erreur interne: install_deploy appelee sans cible." >&2
        exit 1
    fi
    if [[ ! -f "$step" ]]; then
        echo "erreur: snippet de deploiement introuvable : $step" >&2
        exit 1
    fi

    out="$(mktemp)"

    awk -v step="$step" -v perms="$perms" -v envf="$envf" -v spa="$spa" '
        /# >>> PUBLISH_PERMISSIONS <<</ {
            while ((getline line < perms) > 0) print line
            close(perms); next
        }
        # Le seul marqueur avec un defaut : sans fragment, le bloc standard.
        /# >>> PUBLISH_ENVIRONMENT <<</ {
            n = 0
            while ((getline line < envf) > 0) { print line; n++ }
            close(envf)
            if (n == 0) {
                print "      name: production"
                print "      url: ${{ vars.PRODUCTION_URL }}"
            }
            next
        }
        /# >>> PUBLISH_SPA <<</ {
            while ((getline line < spa) > 0) print line
            close(spa); next
        }
        /# >>> PUBLISH_STEP <<</ {
            while ((getline line < step) > 0) print line
            close(step); next
        }
        { print }
    ' "$skeleton" > "$out"

    # Ceinture et bretelles : awk traite un fichier illisible comme un fichier
    # vide. Si un marqueur a survecu, ou si le step Publish n'est pas la, on
    # refuse — c'est exactement l'artefact que ce montage existe pour empecher.
    if grep -q '>>>' "$out" || ! grep -q 'name: Publish' "$out"; then
        echo "erreur: assemblage de deploy.yml incomplet pour '$target'." >&2
        rm -f "$out"; exit 1
    fi

    copy_file "$out" "$TARGET/.github/workflows/deploy.yml"
    rm -f "$out"
}

# copy_tree <source dir> <destination dir>
# Ignore les artefacts de build : un .pyc compilé sur la machine du kit n'a rien
# à faire dans le projet cible, et .claude/ est présenté comme lisible.
copy_tree() {
    local src="$1" dst="$2" rel
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        copy_file "$f" "$dst/$rel"
    done < <(find "$src" \
        \( -name '__pycache__' -o -name '.tdd-red' -o -name 'worktrees' \) -prune -o \
        -type f ! -name '*.pyc' ! -name '.DS_Store' \
                 ! -name '.hook-timings.log' ! -name '.eslint-queue*' -print0)
}

# wire_fastapi <target>
# Câble ce qui peut l'être SANS risque : uniquement les fichiers que CE run vient
# d'installer (donc dont le kit est propriétaire). Un fichier préexistant n'est
# jamais réécrit — il repart en instruction manuelle, comme le reste.
#
# Ce qui est câblé ici : les 6 hooks dans settings.json, @07-backend.md dans
# l'index de CLAUDE.md, app|alembic dans PROTECTED_DIRS.
# Ce qui ne peut pas l'être : 01-stack.md, 00-project.md, 02-architecture.md,
# ship.md, reviewer.md — ils demandent de savoir ce que fait ton projet.
# add_py_hooks <fichier settings.json>  → déclare les 6 hooks de l'addon.
#
# Les trois derniers sont le cycle TDD Python (tdd-require-red-py,
# tdd-freeze-tests-py en Pre, tdd-prove-red-py en Post). Le timeout du prouveur
# est le seul qui compte : il lance pytest, donc il est aligné sur les 180 s du
# tdd-prove-red.sh TypeScript et non sur les 5 s des hooks qui ne font que lire.
add_py_hooks() {
    local target="$1" tmp="$1.tmp"
    jq '
          def add_pre($cmd):
            (.hooks.PreToolUse) |= map(
              if .matcher == "Write|Edit"
              then .hooks += [{type: "command", command: $cmd, timeout: 5}]
              else . end);
          add_pre("$CLAUDE_PROJECT_DIR/.claude/hooks/no-any-type-py.py")
          | add_pre("$CLAUDE_PROJECT_DIR/.claude/hooks/enforce-backend-layers.py")
          | add_pre("$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-require-red-py.py")
          | add_pre("$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-freeze-tests-py.py")
          | (.hooks.PostToolUse) |= map(
              if .matcher == "Write|Edit"
              then .hooks += [{type: "command",
                               command: "$CLAUDE_PROJECT_DIR/.claude/hooks/ruff-on-save.sh",
                               timeout: 30},
                              {type: "command",
                               command: "$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-prove-red-py.py",
                               timeout: 180}]
              else . end)
        ' "$target" > "$tmp" 2>/dev/null && mv "$tmp" "$target"
}

wire_fastapi() {
    local t="$1" f installed_settings=false installed_claude=false installed_guard=false
    for f in "${INSTALLED[@]:-}"; do
        [[ "$f" == "$t/.claude/settings.json" ]] && installed_settings=true
        [[ "$f" == "$t/CLAUDE.md" ]] && installed_claude=true
        [[ "$f" == "$t/.claude/hooks/prevent-destructive-commands.sh" ]] && installed_guard=true
    done

    if ! command -v jq &> /dev/null; then
        echo "  ! jq absent : déclare les 6 hooks Python à la main (README, § 6. Hooks)." >&2
    elif $installed_settings; then
        add_py_hooks "$t/.claude/settings.json" \
            && echo "  câblé : les 6 hooks Python dans .claude/settings.json" \
            || echo "  ! échec du câblage jq : déclare les 6 hooks à la main (README, § 6)." >&2
    elif [[ -e "$t/.claude/settings.json.new" ]]; then
        # Le .new est à nous : on y met les hooks de l'addon, pour que la fusion
        # manuelle porte le fichier complet et pas la moitié.
        add_py_hooks "$t/.claude/settings.json.new" \
            && echo "  ! settings.json préexistant : les 6 hooks sont dans settings.json.new," >&2 \
            && echo "    à fusionner. Non fusionnés = muets." >&2 \
            || echo "  ! déclare les 6 hooks à la main (README, § 6. Hooks)." >&2
    fi

    if $installed_claude && ! grep -q "07-backend.md" "$t/CLAUDE.md"; then
        perl -0pi -e 's{\@\.claude/rules/06-database\.md\n}{\@.claude/rules/06-database.md \@.claude/rules/07-backend.md\n}' "$t/CLAUDE.md"
        echo "  câblé : @07-backend.md dans l'index de règles de CLAUDE.md"
    fi

    if $installed_guard && ! grep -q '^PROTECTED_DIRS=.*alembic' \
                                "$t/.claude/hooks/prevent-destructive-commands.sh"; then
        perl -0pi -e 's{PROTECTED_DIRS="src\|shared}{PROTECTED_DIRS="src|shared|app|alembic}' \
            "$t/.claude/hooks/prevent-destructive-commands.sh"
        echo "  câblé : app|alembic dans PROTECTED_DIRS"
    fi

    # PROTECTED_DIRS est écrit deux fois — le hook l'applique, CLAUDE.md le
    # déclare — et le kit dit partout de changer les deux ensemble. Patcher le
    # seul hook laissait une divergence créée par l'installeur lui-même, que
    # /kit:doctor signalait sur une install neuve.
    if $installed_claude && ! grep -q '`alembic/`' "$t/CLAUDE.md"; then
        perl -0pi -e 's{(Recursive delete on: `src/`, `shared/`,)}{$1 `app/`, `alembic/`,}' "$t/CLAUDE.md"
        echo "  câblé : app/ et alembic/ dans la liste protégée de CLAUDE.md"
    elif ! grep -q '`alembic/`' "$t/CLAUDE.md"; then
        echo "  ! CLAUDE.md préexistant : ajoute \`app/\` et \`alembic/\` à ta liste de" >&2
        echo "    dossiers protégés. PROTECTED_DIRS les a, sa copie déclarée non —" >&2
        echo "    /kit:doctor signale la paire." >&2
    fi
}

# wire_supabase <target>
# Une seule chose, et c'est la plus coûteuse à oublier : le client vit en
# `src/lib/supabase.ts` avec cet addon, alors que le hook garde `lib/client` par
# défaut. Non câblé, `enforce-architecture.py` surveille un module que personne
# n'importe : le vrai client passe partout, silencieusement, pendant que
# 01-stack.md affirme que la couche est couverte. /kit:doctor le signale en
# DIVERGENCE data-client — autant ne pas le créer.
#
# Même règle que wire_fastapi : uniquement le fichier que CE run vient
# d'installer. Un enforce-architecture.py préexistant a peut-être déjà ses
# propres valeurs, et les écraser serait pire que la divergence.
wire_supabase() {
    local t="$1" f installed_arch=false installed_claude=false installed_guard=false
    for f in "${INSTALLED[@]:-}"; do
        [[ "$f" == "$t/.claude/hooks/enforce-architecture.py" ]] && installed_arch=true
        [[ "$f" == "$t/CLAUDE.md" ]] && installed_claude=true
        [[ "$f" == "$t/.claude/hooks/prevent-destructive-commands.sh" ]] && installed_guard=true
    done

    if $installed_arch && grep -q 'DATA_CLIENT_MODULE = "lib/client"' \
                              "$t/.claude/hooks/enforce-architecture.py"; then
        perl -0pi -e 's{DATA_CLIENT_MODULE = "lib/client"}{DATA_CLIENT_MODULE = "lib/supabase"};
                      s{DATA_CLIENT_OWN_PATH = "lib/client\.ts"}{DATA_CLIENT_OWN_PATH = "lib/supabase.ts"}' \
            "$t/.claude/hooks/enforce-architecture.py"
        echo "  câblé : lib/supabase dans DATA_CLIENT_MODULE / DATA_CLIENT_OWN_PATH"
    elif ! $installed_arch && ! grep -q 'DATA_CLIENT_MODULE = "lib/supabase"' \
                                   "$t/.claude/hooks/enforce-architecture.py"; then
        echo "  ! enforce-architecture.py préexistant : mets DATA_CLIENT_MODULE à" >&2
        echo "    \"lib/supabase\" et DATA_CLIENT_OWN_PATH à \"lib/supabase.ts\" à la main." >&2
        echo "    Non câblé, le garde-fou de couche ne garde rien (README, § 2)." >&2
    fi

    # `supabase/` porte les migrations et les edge functions : un rm -rf dessus
    # coûte le schéma. Les deux copies de la liste bougent ensemble, sinon
    # l'installeur fabrique lui-même la divergence que /kit:doctor signale.
    if $installed_guard && ! grep -q '^PROTECTED_DIRS=.*supabase' \
                                "$t/.claude/hooks/prevent-destructive-commands.sh"; then
        perl -0pi -e 's{PROTECTED_DIRS="src\|shared}{PROTECTED_DIRS="src|shared|supabase}' \
            "$t/.claude/hooks/prevent-destructive-commands.sh"
        echo "  câblé : supabase dans PROTECTED_DIRS"
    fi
    if $installed_claude && ! grep -q '`supabase/`' "$t/CLAUDE.md"; then
        perl -0pi -e 's{(Recursive delete on: `src/`, `shared/`,)}{$1 `supabase/`,}' "$t/CLAUDE.md"
        echo "  câblé : supabase/ dans la liste protégée de CLAUDE.md"
    elif ! grep -q '`supabase/`' "$t/CLAUDE.md"; then
        echo "  ! CLAUDE.md préexistant : ajoute \`supabase/\` à ta liste de dossiers" >&2
        echo "    protégés. PROTECTED_DIRS l'a, sa copie déclarée non — /kit:doctor" >&2
        echo "    signale la paire." >&2
    fi
}

# ensure_gitignore <target>
# `.claude/` est versionné — les règles, hooks, agents et commandes SONT le kit.
# Ce que les hooks y ÉCRIVENT à l'exécution ne l'est pas : c'est par session et
# par machine. Le kit connaît cette liste (elle est dans son propre .gitignore) et
# ne la livrait pas : le message de fin ne citait que `.claude/worktrees/`, et les
# six autres arrivaient sans un mot.
#
# Idempotent : le marqueur suffit à ne jamais écrire deux fois. Ajoute seulement,
# ne réécrit ni ne réordonne — un .gitignore existant appartient au projet.
GITIGNORE_MARK="# === LoopKit — état de session ==="
# L'ancien libellé sert encore de clé : un projet installé avant le renommage
# porte celui-là, et sans cette ligne il recevrait un SECOND bloc identique.
GITIGNORE_MARK_LEGACY="# === Claude Workflow Kit — état de session ==="
ensure_gitignore() {
    local gi="$1/.gitignore"
    if [[ -f "$gi" ]] && grep -qF -e "$GITIGNORE_MARK" -e "$GITIGNORE_MARK_LEGACY" "$gi"; then
        return
    fi
    [[ -f "$gi" ]] && printf '\n' >> "$gi"
    cat >> "$gi" <<EOF
$GITIGNORE_MARK
# Écrit à l'exécution par les hooks et le status line. Jamais versionné :
# committer ça, c'est expédier à toute l'équipe les seuils de contexte et les
# marqueurs TDD d'un seul poste.
.claude/worktrees/
.claude/.hook-timings.log
.claude/.eslint-queue
.claude/.eslint-queue.*
.claude/.token-warning
.claude/.token-stop-agents
.claude/.codex-ready
.claude/.quota-warning
.claude/.tdd-red/
# .claude/.tdd-unfrozen n'est délibérément PAS ignoré : toute la raison d'être de
# la liste d'exceptions TDD est d'être visible en review (.claude/rules/05-testing.md).
EOF
    GITIGNORE_TOUCHED=1
}

# La cible du CD est une decision, pas un defaut. Trois chemins :
#   --deploy=<x>        explicite, scriptable, valide contre les fichiers presents
#   terminal, sans flag on demande
#   script, sans flag   `none`, et le workflow echoue tant que personne n'a choisi
# Deux options qui se contredisent ne se departagent pas en silence. Avant, la
# combinaison passait a exit 0 en ignorant --deploy, et le message de fin
# conseillait de relancer avec --deploy — exactement ce que l'utilisateur venait
# de faire.
if $NO_CI && [[ -n "$DEPLOY_TARGET" ]]; then
    echo "erreur: --no-ci et --deploy=$DEPLOY_TARGET se contredisent." >&2
    echo "       --no-ci n'installe aucun workflow, donc aucune cible de CD." >&2
    echo "       Garde l'un des deux." >&2
    exit 1
fi

# La cible est validee des qu'elle est donnee, quoi qu'il arrive ensuite. Sous
# --no-ci, la validation etait court-circuitee et une faute de frappe passait.
if [[ -n "$DEPLOY_TARGET" ]] && ! deploy_is_valid "$DEPLOY_TARGET"; then
    echo "erreur: cible de deploiement inconnue '$DEPLOY_TARGET'." >&2
    echo "       connues : ${DEPLOY_TARGETS[*]}" >&2
    exit 1
fi

if $NO_CI; then
    :   # explicite : rien a demander, rien a installer cote GitHub
elif [[ -z "$DEPLOY_TARGET" && -t 0 ]]; then
    # La premiere question est celle du remote, pas celle de l'hebergeur. Un
    # projet sans depot distant n'a pas un CD a choisir, il n'a pas de CI du
    # tout — et lui en poser la question, c'est lui faire choisir entre deux
    # fichiers morts.
    echo
    echo "Ce projet a-t-il un depot GitHub distant ?"
    echo "  non  = projet local. Aucun workflow installe : ils n'y tourneraient"
    echo "         jamais. Les six gates restent tenues par /ship, comme avant."
    read -r -p "  [O/n] : " answer
    case "${answer:-o}" in
        [nN]*) NO_CI=true ;;
    esac
fi

if $NO_CI; then
    DEPLOY_TARGET=""
elif [[ -n "$DEPLOY_TARGET" ]]; then
    :   # deja validee plus haut
elif [[ -t 0 ]]; then
    echo
    echo "Cible du deploiement (CD) — .github/workflows/deploy.yml"
    echo "  Le CI, lui, est installe tel quel dans tous les cas."
    echo "  Chaque cible listera les secrets GitHub a creer, dans le fichier."
    echo "  'none' = pas encore de prod : le workflow echouera expres."
    echo
    PS3="Ton choix : "
    # `select` sort de la boucle sur EOF (Ctrl-D) en laissant `choice` non
    # defini. Sans le garde qui suit, DEPLOY_TARGET restait vide et l'install
    # continuait jusqu'a produire un deploy.yml sans step Publish.
    select choice in "${DEPLOY_TARGETS[@]}"; do
        if [[ -n "${choice:-}" ]]; then
            DEPLOY_TARGET="$choice"
            break
        fi
        echo "  Reponds par un numero." >&2
    done
    if [[ -z "$DEPLOY_TARGET" ]]; then
        echo >&2
        echo "erreur: aucune cible choisie — installation interrompue." >&2
        echo "       relance avec --deploy=<cible> ou --no-ci." >&2
        exit 1
    fi
    echo
else
    DEPLOY_TARGET="none"
fi

echo "Installation du kit dans : $TARGET"

copy_tree "$KIT_DIR/.claude" "$TARGET/.claude"
copy_file "$KIT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
copy_file "$KIT_DIR/AGENTS.md" "$TARGET/AGENTS.md"
copy_file "$KIT_DIR/codex-handoff.sh" "$TARGET/codex-handoff.sh"
copy_file "$KIT_DIR/workflow.py" "$TARGET/workflow.py"
copy_file "$KIT_DIR/workflow.sh" "$TARGET/workflow.sh"
copy_file "$KIT_DIR/docs/Claude_Workflows.md" "$TARGET/docs/Claude_Workflows.md"
# La checklist d'adaptation part avec le kit : c'est elle que le message de fin
# et le README désignent, et sans elle le projet cible n'a aucune trace de ce
# qu'il reste à remplir.
copy_file "$KIT_DIR/docs/ADAPTATION.md" "$TARGET/docs/ADAPTATION.md"

# Le ledger des faits externes deja etablis. Il est FROID par construction :
# .claude/rules/01-stack.md le nomme, /research et doc-researcher le lisent, et
# aucune session ne le paie. Sans cette copie, 01-stack.md pointe dans le vide
# et /kit:doctor (settled-ledger) le signale des la premiere execution.
copy_file "$KIT_DIR/docs/research-cache/settled.md" "$TARGET/docs/research-cache/settled.md"

# Le miroir serveur des gates. ci.yml est livre tel quel : il ne depend que des
# six scripts declares par 00-project.md, jamais de la forme du code.
# deploy.yml, lui, est ASSEMBLE — squelette + le step Publish de la cible
# choisie. Sur `none`, ce step est un `exit 1` : un CD non configure qui
# "reussit" a ne rien deployer est pire que pas de CD.
# Le contrat est dans .claude/skills/templates/ci.md.
if $NO_CI; then
    echo "  Aucun workflow GitHub (--no-ci ou projet local)."
else
    copy_file "$KIT_DIR/templates/github/ci.yml" "$TARGET/.github/workflows/ci.yml"
    install_deploy "$DEPLOY_TARGET"
fi

if $WITH_SUPABASE; then
    echo "Addon Supabase inclus."
    ADDON="$KIT_DIR/addons/supabase"
    copy_override "$ADDON/rules/01-stack.md" "$TARGET/.claude/rules/01-stack.md"
    copy_override "$ADDON/rules/06-database.md" "$TARGET/.claude/rules/06-database.md"
    copy_override "$ADDON/commands/database/migration.md" "$TARGET/.claude/commands/database/migration.md"
    for f in "$ADDON/skills/patterns/"*.md; do
        copy_file "$f" "$TARGET/.claude/skills/patterns/$(basename "$f")"
    done
    for f in "$ADDON/skills/templates/"*.md; do
        copy_file "$f" "$TARGET/.claude/skills/templates/$(basename "$f")"
    done
    # Le layer _shared/ des edge functions : du code, pas de la doc.
    copy_tree "$ADDON/functions" "$TARGET/supabase/functions"
    copy_file "$ADDON/README.md" "$TARGET/.claude/skills/patterns/SUPABASE-ADDON.md"
    wire_supabase "$TARGET"
fi

if $WITH_FASTAPI; then
    echo "Addon FastAPI inclus."
    ADDON="$KIT_DIR/addons/fastapi"
    copy_override "$ADDON/rules/06-database.md" "$TARGET/.claude/rules/06-database.md"
    copy_override "$ADDON/commands/database/migration.md" \
                  "$TARGET/.claude/commands/database/migration.md"
    copy_file "$ADDON/rules/07-backend.md" "$TARGET/.claude/rules/07-backend.md"
    # Le rationnel va dans guides/, jamais chargé au démarrage — même partage que
    # le coeur du kit : un piège reste dans la règle, une rétrospective part ici.
    copy_file "$ADDON/guides/07-backend.md" "$TARGET/.claude/guides/07-backend.md"
    for f in "$ADDON/commands/backend/"*.md; do
        copy_file "$f" "$TARGET/.claude/commands/backend/$(basename "$f")"
    done
    copy_file "$ADDON/commands/refactor/clean-python.md" \
              "$TARGET/.claude/commands/refactor/clean-python.md"
    for f in "$ADDON/skills/patterns/"*.md; do
        copy_file "$f" "$TARGET/.claude/skills/patterns/$(basename "$f")"
    done
    copy_file "$ADDON/skills/templates/endpoint.md" \
              "$TARGET/.claude/skills/templates/endpoint.md"
    # Extensions explicites, jamais `*` : le glob nu ramasse aussi le
    # `__pycache__/` que laisse le moindre import des hooks Python, et copy_file
    # fait un `cp` sans -r — il échoue sur un dossier. Un run d'install qui casse
    # là laisse le projet à moitié câblé.
    for f in "$ADDON/hooks/"*.py "$ADDON/hooks/"*.sh; do
        [[ -f "$f" ]] || continue
        copy_file "$f" "$TARGET/.claude/hooks/$(basename "$f")"
    done
    copy_file "$ADDON/README.md" "$TARGET/.claude/skills/patterns/FASTAPI-ADDON.md"
    wire_fastapi "$TARGET"

    if $WITH_SUPABASE; then
        echo "  ! Les deux addons écrivent 06-database.md et database/migration.md :" >&2
        echo "    FastAPI a gagné." >&2
        echo "    Fusionne à la main si le projet utilise vraiment les deux." >&2
    fi
fi

chmod +x "$TARGET/.claude/hooks/"*.sh "$TARGET/.claude/hooks/"*.py 2>/dev/null || true
chmod +x "$TARGET/codex-handoff.sh" 2>/dev/null || true
chmod +x "$TARGET/workflow.py" "$TARGET/workflow.sh" 2>/dev/null || true

GITIGNORE_TOUCHED=0
ensure_gitignore "$TARGET"

echo
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "Déjà présents — écrits en .new, à fusionner à la main :"
    printf '  %s\n' "${SKIPPED[@]}"
    echo
fi

# Un settings.json non fusionné = AUCUN hook déclaré. Tout le kit devient
# déclaratif : les règles sont là, rien ne les tient. Ça ne peut pas se perdre
# dans la liste générique ci-dessus.
if [[ -e "$TARGET/.claude/settings.json.new" ]]; then
    cat >&2 <<'EOF'
  !! settings.json existait déjà — le kit a écrit settings.json.new À CÔTÉ.
     Tant que les deux ne sont pas fusionnés, AUCUN hook n'est déclaré :
     ni TDD, ni no-any, ni archi, ni protection des fichiers. Les règles
     sont installées, rien ne les applique.
     Fusionne les blocs "hooks" (et "worktree") de .claude/settings.json.new
     dans ton .claude/settings.json, puis supprime le .new.

EOF
fi

if [[ "$GITIGNORE_TOUCHED" -eq 1 ]]; then
    echo "  .gitignore : bloc « état de session » ajouté (9 chemins écrits par les hooks)."
    echo
fi

if $NO_CI; then
    cat <<'EOF'
Pas de CI : aucun workflow installé. Les six rôles de gate n'ont pas bougé
d'un pouce — c'est /ship qui les tient, avant chaque commit, comme avant.
Le CI n'a jamais été qu'une SECONDE copie, pour ce que /ship ne peut pas
couvrir : une machine qui n'est pas la tienne.

Le jour où tu pousses sur un dépôt distant :
  ./install.sh <ce projet> --deploy=<cible>
Il écrira les workflows sans toucher au reste (tout le reste part en .new).

EOF
else
    cat <<'EOF'
CI/CD — .github/workflows/ci.yml part opérationnel (les six rôles de gate,
miroir serveur de /ship). deploy.yml a été assemblé pour la cible choisie ;
sur `none` son étape Publish échoue exprès tant que tu n'en as pas nommé une.
Déclare le local ET la prod dans CLAUDE.md, section Environment.
Contrat : .claude/skills/templates/ci.md.

EOF
fi

cat <<'EOF'
À remplir avant de lancer quoi que ce soit :

  grep -rnE "FILL|CONFIGURE" .claude/ CLAUDE.md docs/

Dans l'ordre : 01-stack.md (client de données) → enforce-architecture.py
(DATA_CLIENT_MODULE + COMPOSITION_ROOTS) → 00-project.md (scripts, dont lint)
→ 02-architecture.md (backend) → 06-database.md → CLAUDE.md → 03-conventions.md
(langues).

Puis, avant la première feature — ce n'est pas un FILL, c'est un prérequis :
scaffolder src/lib/result.ts, src/lib/errors.ts et src/lib/queryClient.ts
depuis .claude/skills/templates/lib-core.md. Tous les patterns les importent,
et les defauts de React Query (staleTime, retry) ne sont nulle part ailleurs.

Addon installé ? Son câblage n'est PAS automatique :
  .claude/skills/patterns/SUPABASE-ADDON.md  (DATA_CLIENT_MODULE et
  PROTECTED_DIRS sont câblés automatiquement sur une install neuve ; restent
  à faire : la section Backend de 02-architecture.md, les FILL de 01-stack.md,
  le gate edge-function de 00-project.md. Puis vérifier le layer copié :
  cd supabase/functions && deno check _shared/**/*.ts)
  .claude/skills/patterns/FASTAPI-ADDON.md   (les hooks, @07-backend.md et
  PROTECTED_DIRS sont câblés automatiquement sur une install neuve ; restent à
  faire : 01-stack.md, 00-project.md, 02-architecture.md, EXTERNAL_CLIENTS,
  et surtout les gates backend dans commands/ship.md + 07-backend.md dans
  agents/reviewer.md)

Lanceur supervisé recommandé :
  ./workflow.sh
  À 90% il checkpoint, à 95% il arrête les nouveaux agents, à 97% il passe à
  Codex. Une limite d'usage détectée dans la sortie déclenche le même relais.

Relais manuel :
  /handoff:codex <artefact> puis ./codex-handoff.sh <handoff>

Détail : docs/ADAPTATION.md.
EOF
