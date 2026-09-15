# capability-map.sh — shared readers for references/runtime-tools.md
# =============================================================================
#
# WHY THIS FILE EXISTS
#   `gen-gemini-commands.sh` and `portability-lint.sh` both have to answer the
#   same two questions about the capability map, and both answered them with
#   their own byte-for-byte copy of the same pipeline:
#
#     - which ids does the map declare?      (canonical_ids)
#     - which ids does this file cite?       (cited_ids)
#
#   Two copies of a parser for one file format is a drift generator. The map's
#   fence markers, the backtick stripping, the `capability:` prefix — change any
#   of them and one script silently keeps the old reading. The linter would then
#   pass an id the generator classifies differently, which is exactly the
#   runtime-divergence the map exists to prevent.
#
# CONTRACT
#   The caller sets `MAP` to references/runtime-tools.md BEFORE calling either
#   function. It is deliberately not resolved here: the two callers resolve the
#   repo root differently (portability-lint.sh needs `pwd -P` to survive the
#   plugins/harness-ops symlink, and says why in its own header), and a second
#   resolution rule in a third file is the drift this file exists to remove.
#
#   Both functions are `|| true` at the end: an empty result is a legitimate
#   answer, and the callers run under `set -e`.

# canonical_ids — every id the map declares, one per line.
canonical_ids() {
  [ -f "$MAP" ] || return 0
  awk '/BEGIN CANONICAL-IDS/{f=1;next} /END CANONICAL-IDS/{f=0} f' "$MAP" \
    | tr -d '`' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -E '^[a-z][a-z0-9-]*$' || true
}

# cited_ids <file> — every `capability:<id>` the file cites, deduped and sorted.
cited_ids() {
  [ -f "$1" ] || return 0
  grep -oE 'capability:[a-z][a-z0-9-]*' "$1" | sed 's/^capability://' | sort -u || true
}
