#!/usr/bin/env bash
#
# Not a hook — a reader. Aggregates .claude/.hook-timings.log written by
# hook-lib.sh (and by enforce-architecture.py, same format).
#
#   .claude/hooks/hook-timings-report.sh            # whole log
#   .claude/hooks/hook-timings-report.sh --since 30 # last 30 minutes
#   .claude/hooks/hook-timings-report.sh --reset    # start a clean campaign
#
# Read the TOTAL column, not the mean. A 40ms hook fired 300 times costs more
# wall-clock than a 3s hook fired twice, and only one of the two is worth
# touching.
#

set -e

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
LOG="$ROOT/.claude/.hook-timings.log"
SINCE_MIN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) SINCE_MIN="$2"; shift 2 ;;
        --reset) : > "$LOG"; echo "Log remis à zéro : $LOG"; exit 0 ;;
        *) echo "usage: $0 [--since <minutes>] [--reset]" >&2; exit 1 ;;
    esac
done

if [[ ! -s "$LOG" ]]; then
    echo "Aucune mesure dans $LOG."
    echo "Les hooks écrivent dedans dès qu'ils tournent (CWK_HOOK_TIMING=1, le défaut)."
    exit 0
fi

CUTOFF=0
if [[ "$SINCE_MIN" -gt 0 ]]; then
    CUTOFF=$(( ($(date +%s) - SINCE_MIN * 60) * 1000 ))
fi

ROWS=$(awk -F'\t' -v cutoff="$CUTOFF" '
    $1 >= cutoff {
        n[$2]++; total[$2] += $3
        if ($3 > max[$2]) max[$2] = $3
        grand += $3; calls++
    }
    END {
        if (calls == 0) exit 1
        for (h in n)
            # field 1 = raw total in ms, used only to sort, stripped below
            printf "%d|%-30s %7d %9.1fs %8.0fms %8.0fms %6.1f%%\n", \
                total[h], h, n[h], total[h]/1000, total[h]/n[h], max[h], 100*total[h]/grand
        printf "0|%-30s %7d %9.1fs\n", "TOTAL", calls, grand/1000
    }
' "$LOG") || { echo "Aucune mesure dans la fenêtre demandée."; exit 0; }

printf "%-30s %7s %11s %9s %9s %7s\n" "HOOK" "APPELS" "TOTAL" "MOYEN" "MAX" "PART"
sort -t'|' -k1,1nr <<< "$ROWS" | cut -d'|' -f2-

cat <<'EOF'

Cumul brut. Les hooks d'un même événement peuvent tourner en parallèle : ce
chiffre majore l'attente réelle, il ne la mesure pas. Lire la colonne TOTAL,
pas MOYEN — un hook à 40ms tiré 300 fois coûte plus cher qu'un hook à 3s tiré
deux fois, et un seul des deux vaut qu'on y touche.
EOF
