#!/bin/zsh
# Captures raw App Store screenshots from a simulator using the debug-only -Shot staging.
# Usage: scripts/capture-screenshots.sh <simulator-udid> <output-dir>
set -u
U=$1
OUT=$2
mkdir -p "$OUT"
BASE=(-FakeClock YES -soundPack phoneScreen -sound NO)

shot() { # name delay args...
  local name=$1 delay=$2; shift 2
  xcrun simctl terminate $U app.shattter.glass >/dev/null 2>&1
  sleep 0.5
  xcrun simctl launch $U app.shattter.glass "${BASE[@]}" "$@" >/dev/null
  sleep $delay
  xcrun simctl io $U screenshot --mask=ignored "$OUT/$name.png" >/dev/null 2>&1
}

shot 1-hero 2.9 -Shot hero -screen glass -hitsToShatter 0 -crackgate NO -Palette 0
for d in 1.6 1.8 2.0 2.2; do shot "2-shatter-$d" $d -Shot shatter -screen glass -hitsToShatter 1 -shatterStyle explode -autoRepair NO -crackgate NO -Palette 1; done
shot 3-lock 3.2 -Shot lock -screen lockScreen -hitsToShatter 0 -crackgate NO
shot 4-patterns 3.4 -Shot patterns -screen glass -hitsToShatter 0 -crackgate NO -Palette 2
shot 5-crackgate 7.0 -Shot crackgate -screen homeScreen -crackgate YES -gotcha YES -autoRepair NO
shot 6-broken 6.0 -Shot broken -screen messages -hitsToShatter 1 -shatterStyle crumble -gotcha YES -autoRepair NO -crackgate NO
shot 7-options 3.6 -ShowOptions -screen glass -crackgate NO -Palette 4
xcrun simctl terminate $U app.shattter.glass >/dev/null 2>&1
