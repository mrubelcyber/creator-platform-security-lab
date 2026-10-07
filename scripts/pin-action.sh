#!/usr/bin/env bash
# Resolve a GitHub Action tag to its full commit SHA (look it up, never guess). Lab 13, SEC-2553.
# Usage: scripts/pin-action.sh OWNER/REPO        -> newest 5 release tags
#        scripts/pin-action.sh OWNER/REPO TAG    -> OWNER/REPO@SHA # TAG
set -euo pipefail
repo="${1:?usage: pin-action.sh OWNER/REPO [TAG]}"
tag="${2:-}"
refs=$(git ls-remote --tags "https://github.com/${repo}.git")
if [ -z "$tag" ]; then
  awk '{sub("refs/tags/","",$2); print $2}' <<<"$refs" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -5
  exit 0
fi
sha=$(awk -v t="refs/tags/${tag}^{}" '$2==t {print $1}' <<<"$refs")
[ -n "$sha" ] || sha=$(awk -v t="refs/tags/${tag}" '$2==t {print $1}' <<<"$refs")
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "tag ${tag} not found in ${repo}" >&2; exit 1; }
echo "${repo}@${sha} # ${tag}"
