#!/usr/bin/env bash
# Push wiki/ to the GitHub wiki repository.
# Author: Edson Lourenço
#
# GitHub creates OWNER/REPO.wiki.git only after one page has been saved in the
# browser. Open the wiki tab once, save the suggested page, then run this.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
remote=${1:-https://github.com/edsonlourenco/hearthline.wiki.git}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if ! git clone "$remote" "$work/wiki"; then
  printf 'The wiki remote is not ready yet.\n' >&2
  printf 'Open https://github.com/edsonlourenco/hearthline/wiki , save the first page, and run this script again.\n' >&2
  exit 1
fi

find "$work/wiki" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -a "$root/wiki/." "$work/wiki/"
git -C "$work/wiki" add -A
if git -C "$work/wiki" diff --cached --quiet; then
  printf 'Wiki is already up to date.\n'
  exit 0
fi
author_name=$(git -C "$root" log -1 --format='%an')
author_email=$(git -C "$root" log -1 --format='%ae')
GIT_AUTHOR_NAME=$author_name \
GIT_AUTHOR_EMAIL=$author_email \
GIT_COMMITTER_NAME=$author_name \
GIT_COMMITTER_EMAIL=$author_email \
  git -C "$work/wiki" commit -m "Publish the Hearthline wiki."
git -C "$work/wiki" push origin HEAD
printf 'Wiki published.\n'
