#!/usr/bin/env bash
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lock-expected-pid)
HOME_ROOT="$TMP_ROOT/home"
PI="$TMP_ROOT/pi"
mkdir -p "$HOME_ROOT/state" "$HOME_ROOT/config"
chmod 700 "$HOME_ROOT" "$HOME_ROOT/state" "$HOME_ROOT/config"
ln -s "$(command -v bash)" "$PI"

printf '88888888\n' > "$HOME_ROOT/state/.lock"
if FM_HOME="$HOME_ROOT" FM_ROOT_OVERRIDE="$ROOT" "$PI" -c 'exec "$FM_ROOT_OVERRIDE/bin/fm-lock.sh" --expected-pid 77777777' > "$HOME_ROOT/state/mismatch.out" 2>&1; then
  fail "expected-pid CAS accepted a replaced lock incarnation"
fi
[ "$(cat "$HOME_ROOT/state/.lock")" = 88888888 ] || fail "expected-pid mismatch mutated the newer lock"

printf '99999999\n' > "$HOME_ROOT/state/.lock"
FM_HOME="$HOME_ROOT" FM_ROOT_OVERRIDE="$ROOT" "$PI" -c 'exec "$FM_ROOT_OVERRIDE/bin/fm-lock.sh" --expected-pid 99999999' > "$HOME_ROOT/state/match.out" 2>&1 \
  || fail "expected-pid CAS refused the exact stale owner: $(cat "$HOME_ROOT/state/match.out")"
if [ "$(cat "$HOME_ROOT/state/.lock")" = 99999999 ]; then
  fail "expected-pid CAS did not publish the new owner"
fi
grep -q 'lock acquired: harness pid' "$HOME_ROOT/state/match.out" \
  || fail "expected-pid CAS did not report verified acquisition"

SELF_HOME="$TMP_ROOT/self-home"
mkdir -p "$SELF_HOME/state" "$SELF_HOME/config"
if FM_HOME="$SELF_HOME" FM_ROOT_OVERRIDE="$ROOT" "$PI" -c \
  'printf "%s\n" "$$" > "$FM_HOME/state/.lock"; exec "$FM_ROOT_OVERRIDE/bin/fm-lock.sh" --expected-pid 77777777' \
  > "$SELF_HOME/self-mismatch.out" 2>&1; then
  fail "expected-pid CAS accepted a mismatch through the owned-lock fast path"
fi
[ "$(cat "$SELF_HOME/state/.lock")" != 77777777 ] || fail "owned-lock mismatch rewrote the lock"
[ ! -e "$SELF_HOME/state/.lock-session" ] || fail "owned-lock mismatch wrote a session sidecar"
grep -q 'expected stale session lock owner changed' "$SELF_HOME/self-mismatch.out" \
  || fail "owned-lock mismatch did not fail at the exact-PID check"

pass "fm-lock expected-pid CAS refuses replacement and reclaims only the exact stale incarnation"
