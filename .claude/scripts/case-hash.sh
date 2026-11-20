#!/usr/bin/env bash
# Usage: case-hash.sh '<new case title>'
#
# Prints the sha256 (hex) of its single argument, UTF-8, no newline added: the digest a plan-gate
# row `<test path> | <case id> | <sha256>` carries, recomputed by the freeze hooks in rows mode
# (docs/specs/loop-to-pr.md, "Hash producer"). Reads no stdin, writes no file.

if [[ $# -ne 1 ]]; then
    echo "usage: case-hash.sh '<new case title>'" >&2
    exit 2
fi
exec python3 -I -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode("utf-8", "surrogateescape")).hexdigest())' "$1" </dev/null
