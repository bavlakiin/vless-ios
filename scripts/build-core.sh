#!/bin/bash
# Сборка VlessCore.xcframework (Xray-core + tun2socks) для iOS 12+.
# Запускать на Маке из корня репозитория:  ./scripts/build-core.sh
set -euo pipefail

IOS_MIN=12.0
OUT_DIR="$(dirname "$0")/../XrayFramework"
WORK="$(mktemp -d /tmp/vlesscore.XXXXXX)"

echo "== 1/3 Клонируем зависимости =="
cp -r "$(dirname "$0")/../core-go" "$WORK/core"
cd "$WORK/core"
GO111MODULE=on go mod tidy          # подтянет xray-core 1.8.24 и tun2socks 2.5.0

echo "== 2/3 gomobile bind =="
GO111MODULE=on go install golang.org/x/mobile/bind@latest

mkdir -p "$OUT_DIR"
GO111MODULE=on gomobile bind \
  -target=ios -iosversion "$IOS_MIN" \
  -ldflags="-s -w" \
  -o "$OUT_DIR/VlessCore.xcframework" \
  ./vlesscore

echo "== 3/4 Чистим симуляторные куски (не нужны для устройства) — пропускаем =="

echo "Готово: $OUT_DIR/VlessCore.xcframework"
echo "Теперь: xcodegen && открой VlessApp.xcodeproj в Xcode"
