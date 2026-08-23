#!/bin/bash
# Сборка VlessCore.xcframework (Xray-core + go-tun2socks/lwIP) для iOS 12+.
# Запускать на Маке из корня репозитория:  ./scripts/build-core.sh
set -euo pipefail

IOS_MIN=12.0
OUT_DIR="$(dirname "$0")/../XrayFramework"

echo "== 1/3 Подготавливаем модуль ядра =="
cd "$(dirname "$0")/../core-go"
GO111MODULE=on go mod tidy   # подтянет xray-core 1.8.24 и go-tun2socks 1.16.11 (+ indirect)

echo "== 2/3 Устанавливаем gomobile =="
GO111MODULE=on go install golang.org/x/mobile/cmd/gomobile@latest
GO111MODULE=on go install golang.org/x/mobile/bind@latest
export PATH="$PATH:$(go env GOPATH)/bin"
gomobile init

echo "== 3/3 gomobile bind =="
mkdir -p "$OUT_DIR"
GO111MODULE=on gomobile bind \
  -target=ios -iosversion "$IOS_MIN" \
  -ldflags="-s -w" \
  -o "$OUT_DIR/VlessCore.xcframework" \
  ./vlesscore

echo "Готово: $OUT_DIR/VlessCore.xcframework"
echo "Далее: замените REPLACE_WITH_YOUR_TEAM_ID в project.yml и выполните: xcodegen"
