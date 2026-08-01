#!/usr/bin/env bash
#
# Verifies that every vendored Helm subchart tarball matches its Chart.lock.
#
# Helm renders whatever is physically in charts/. A Chart.yaml/Chart.lock bump
# without the matching tarball changes no rendered output at all, so ArgoCD sees
# no diff, stays Synced/Healthy, and the upgrade never reaches the cluster --
# silently. This check turns that into a hard failure.
#
# Usage: helper/verify-vendored-charts.sh [chart-dir ...]
# With no arguments, every infrastructure/*/Chart.lock is checked.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  chart_dirs=("$@")
else
  chart_dirs=()
  for lock in "$repo_root"/infrastructure/*/Chart.lock; do
    [ -e "$lock" ] || continue
    chart_dirs+=("$(dirname "$lock")")
  done
fi

failed=0

for chart_dir in "${chart_dirs[@]}"; do
  lock="$chart_dir/Chart.lock"
  if [ ! -f "$lock" ]; then
    echo "SKIP  ${chart_dir#"$repo_root"/}: no Chart.lock"
    continue
  fi

  name="$(basename "$chart_dir")"

  # Chart.lock is a flat list of "- name: X" / "  version: Y" pairs. Collect the
  # tarball filename Helm would write for each dependency.
  expected=()
  while IFS=$'\t' read -r dep_name dep_version; do
    expected+=("$dep_name-$dep_version.tgz")
  done < <(awk '
    /^- name:|^  - name:/ { dep = $NF }
    /^  version:|^    version:/ { if (dep != "") { print dep "\t" $NF; dep = "" } }
  ' "$lock")

  if [ "${#expected[@]}" -eq 0 ]; then
    echo "FAIL  $name: could not parse any dependency out of Chart.lock"
    failed=1
    continue
  fi

  chart_failed=0

  # Every locked dependency must be present...
  for tgz in "${expected[@]}"; do
    if [ ! -f "$chart_dir/charts/$tgz" ]; then
      echo "FAIL  $name: Chart.lock expects charts/$tgz, which is missing."
      echo "      Run 'helm dependency build ${chart_dir#"$repo_root"/}' and commit the result."
      chart_failed=1
    fi
  done

  # ...and nothing else, or Helm would render a stale subchart alongside it.
  for present in "$chart_dir"/charts/*.tgz; do
    [ -e "$present" ] || continue
    base="$(basename "$present")"
    match=0
    for tgz in "${expected[@]}"; do
      [ "$base" = "$tgz" ] && match=1
    done
    if [ "$match" -eq 0 ]; then
      echo "FAIL  $name: charts/$base is not in Chart.lock. Stale tarballs override the pinned version."
      chart_failed=1
    fi
  done

  if [ "$chart_failed" -eq 0 ]; then
    echo "OK    $name: ${expected[*]}"
  else
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo
  echo "Vendored charts are out of sync with Chart.lock."
  exit 1
fi

echo
echo "All vendored charts match their Chart.lock."
