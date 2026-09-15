#!/usr/bin/env bash
# Prove the Halmos form of the Kontrol list invariants (scripts/halmos-from-kontrol.py).
#
# Two of the 16 are left to Kontrol, which still proves all of them:
# - RepoTokenList testGetPresentTotalValue: the solver cannot decide it (TIMEOUT with a 10-minute
#   limit per query).
# - TermAuctionList testInsertPendingNewOffer: it etches code at a symbolic address, and halmos
#   0.3.3's vm.etch needs a concrete one.
#
# Each contract runs exactly the test functions its generated file declares, minus the one named
# here. The job fails unless all 14 pass with every path explored, so neither the set left to Kontrol
# nor the set of proofs can change without this script changing.
set -euo pipefail

EXPECTED_PROOFS=14
GENERATED=halmos/generated
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
selected=0

prove() {  # prove <generated file> <contract> <test left to Kontrol>
  local names count
  names="$(grep -oE 'function test[A-Za-z0-9_]+' "${GENERATED}/$1" | awk '{print $2}' | grep -vx "$3" | paste -sd'|' - || true)"
  count="$(tr '|' '\n' <<< "$names" | grep -c . || true)"
  selected=$((selected + count))
  # The pattern matches whether halmos compares a function's name or its full signature.
  FOUNDRY_PROFILE=halmos halmos --match-contract "^$2$" --match-test "^(${names})(\\(|$)" \
    --loop 4 --solver-timeout-assertion 5m -st 2>&1 | tee -a "$log"
}

python3 scripts/halmos-from-kontrol.py
status=0
prove RepoTokenListInvariants.t.sol HalmosRepoTokenListInvariantsTest testGetPresentTotalValue || status=1
prove TermAuctionListInvariants.t.sol HalmosTermAuctionListInvariantsTest testInsertPendingNewOffer || status=1

plain="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
passes="$(grep -cE '^\[PASS\] test' <<< "$plain" || true)"
if [ "$selected" -ne "$EXPECTED_PROOFS" ]; then
  echo "selected ${selected} proofs from the generated suites, expected ${EXPECTED_PROOFS}: the Kontrol suites changed" >&2
  status=1
fi
if grep -qE '^\[(FAIL|ERROR|TIMEOUT)\]' <<< "$plain"; then
  echo "a proof failed, errored or timed out" >&2
  status=1
fi
if grep -q "not been fully" <<< "$plain"; then
  echo "a proof reached the loop bound, so its result is partial" >&2
  status=1
fi
if [ "$passes" -ne "$EXPECTED_PROOFS" ]; then
  echo "expected ${EXPECTED_PROOFS} passing proofs, got ${passes}" >&2
  status=1
fi
exit "$status"
