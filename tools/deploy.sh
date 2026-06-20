#!/usr/bin/env bash
# minho2 — 빌드 + GitHub Pages 배포 (한 방)
# 사용: bash tools/deploy.sh
# 결과: https://joyhunny.github.io/minho2/  (1~2분 뒤 반영)
set -e

GODOT="${GODOT:-$HOME/godot/Godot_v4.3-stable_linux.x86_64}"
PROJ="$HOME/play/minho2"
cd "$PROJ"

echo "1) 리소스 가져오기(import)…"
"$GODOT" --headless --path . --import

echo "2) 웹으로 내보내기(export)…"
mkdir -p build
"$GODOT" --headless --path . --export-release "Web" build/index.html

echo "3) gh-pages 브랜치로 배포…"
rm -rf /tmp/minho2-pages
git worktree add -B gh-pages /tmp/minho2-pages >/dev/null 2>&1
cd /tmp/minho2-pages
git rm -rf . >/dev/null 2>&1 || true
cp "$PROJ"/build/* .
touch .nojekyll
git add -A
git -c user.name=joyhunny -c user.email=joyhunny@gmail.com commit -q -m "deploy: web build"
git push -f origin gh-pages
cd "$PROJ"
git worktree remove /tmp/minho2-pages --force

echo "배포 완료 → https://joyhunny.github.io/minho2/  (반영까지 1~2분)"
