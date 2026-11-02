#!/usr/bin/env bash
# Build da versão web do MistakeMap dentro da Vercel (integração Git).
#
# A Vercel não traz o Flutter na imagem de build, então este script baixa o
# SDK fixado (mesma versão do CI), roda o build web de release e deixa o
# resultado em appmistakemap/build/web, que o vercel.json da raiz publica.
# Não usa segredo nenhum: a chave do Supabase no app é a pública (anon).
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK_PARENT="${FLUTTER_SDK_PARENT:-$ROOT/.vercel-flutter}"
FLUTTER="$SDK_PARENT/flutter/bin/flutter"

if [ ! -x "$FLUTTER" ]; then
  mkdir -p "$SDK_PARENT"
  archive="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  echo "Baixando Flutter ${FLUTTER_VERSION}..."
  if command -v xz >/dev/null 2>&1; then
    curl -fsSL "$archive" | tar -xJ -C "$SDK_PARENT"
  else
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$SDK_PARENT/flutter"
  fi
fi

# A imagem de build roda como root; o Flutter avisa, mas funciona.
git config --global --add safe.directory "$SDK_PARENT/flutter" || true
export FLUTTER_SUPPRESS_ANALYTICS=true
"$FLUTTER" config --no-analytics >/dev/null 2>&1 || true
"$FLUTTER" --version

cd "$ROOT/appmistakemap"
"$FLUTTER" pub get
"$FLUTTER" build web --release

# O sqlite3.wasm do web/ precisa casar com o pacote sqlite3 do pubspec.lock;
# se faltar no build, o Caderno offline quebra no navegador.
test -s build/web/sqlite3.wasm
test -s build/web/sqflite_sw.js
test -s build/web/main.dart.js
echo "Build web pronto em appmistakemap/build/web"
