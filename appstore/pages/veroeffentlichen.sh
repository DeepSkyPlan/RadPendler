#!/bin/zsh
# Veröffentlicht die Support- und die Datenschutzseite: je Ordner hier ein öffentliches Repo
# DeepSkyPlan/<ordner> mit GitHub Pages aus main → https://deepskyplan.github.io/<ordner>/
#   appstore/pages/veroeffentlichen.sh [radpendler-app|radpendler-privacy …]
set -eu
cd "${0:A:h}"
pages=("$@"); (( $#pages )) || pages=(radpendler-app radpendler-privacy)
for page in $pages; do
  tmp=$(mktemp -d)
  if gh api "repos/DeepSkyPlan/$page" --silent 2>/dev/null; then
    gh repo clone "DeepSkyPlan/$page" "$tmp/$page" -- -q
  else
    gh repo create "DeepSkyPlan/$page" --public -d "RadPendler: $page"
    git init -q -b main "$tmp/$page"
    git -C "$tmp/$page" remote add origin "https://github.com/DeepSkyPlan/$page.git"
  fi
  rsync -a --delete --exclude .git "$page/" "$tmp/$page/"
  git -C "$tmp/$page" add -A
  if git -C "$tmp/$page" diff --cached --quiet; then
    echo "$page: unverändert"
  else
    git -C "$tmp/$page" commit -qm "Stand aus RadPendler/appstore/pages ($(date +%F))"
    git -C "$tmp/$page" push -q -u origin main
    gh api -X POST "repos/DeepSkyPlan/$page/pages" -f 'source[branch]=main' -f 'source[path]=/' >/dev/null 2>&1 || true
    echo "$page: gepusht → https://deepskyplan.github.io/$page/"
  fi
  rm -rf "$tmp"
done
