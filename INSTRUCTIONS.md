# Инструкция для агента/модели на Маке

Репозиторий — VLESS-клиент для iOS 12 (iPhone 6) по образцу Happ Plus:
приложение на UIKit + Packet Tunnel extension, ядро Xray-core 1.8.24 +
tun2socks, собираемое через gomobile. Цель — довести до собираемого и
работающего на устройстве состояния. Делай по порядку:

## Этап 1 — ядро

1. Установи зависимости: `brew install go@1.20 xcodegen` (плюс Xcode;
   для установки на iOS 12 нужен Xcode 10.3 на Mojave, свежий Xcode
   подойдёт для сборки).
2. Зайди в `core-go/vlesscore/vlesscore.go`. Это обёртка для gomobile с
   функциями `XrayStart/XrayStop/Tun2SocksStart/Tun2SocksStop`.
   Запусти `./scripts/build-core.sh`.
3. Скрипт почти наверняка упадёт из-за несовпадения API: tun2socks v2.5.0
   может не иметь `option.WithTunAddress/WithTunMask/WithTunDNS/InjectTunFD`
   с такими именами, а у xray-core функция разбора JSON может называться
   иначе, чем `json.FromJSON`, и может отсутствовать
   `_ "github.com/xtls/xray-core/main/distro/all"`. Открой исходники
   скачанных модулей в `$(go env GOMODCACHE)` и поправь обёртку под
   реальные сигнатуры. Для tun2socks ключевое: движок должен использовать
   УЖЕ ОТКРЫТЫЙ tun-дескриптор (fd из `NEPacketTunnelFlow`), а не создавать
   свой — смотри в их репо `engine/tun` и mobile-примеры. Если точной опции
   для готового fd нет, используй `option.WithFileDescriptor`/аналог или
   подход из их `core/engine.go`.
4. Добейся, чтобы `gomobile bind -target=ios -iosversion 12.0 ... ./vlesscore`
   выдал `XrayFramework/VlessCore.xcframework`. Если gomobile ругается на
   версию Go — ставь именно go 1.20.x.

## Этап 2 — Xcode-проект

5. В `project.yml` замени `REPLACE_WITH_YOUR_TEAM_ID` на Team ID из Apple
   Developer. Запусти `xcodegen`, открой `VlessApp.xcodeproj`.
6. Собери оба таргета. Swift-код написан под iOS 12, но имена функций из
   фреймворка после gomobile могут отличаться (gomobile генерирует префиксы
   вида `VlesscoreXrayStart` вместо `VlessCoreXrayStart`) — открой
   сгенерированный `VlessCore.framework/Headers/VlessCore.h` и приведи
   вызовы в `PacketTunnelProvider.swift` к точным именам.
7. Проверь: у обоих таргетов есть entitlements (App Group
   `group.vless.shared`, packet-tunnel-provider), bundle id extension =
   `<id приложения>.VlessPacketTunnel` — иначе VPN не стартует.

## Этап 3 — устройство

8. Подключи iPhone 6, Run. Первый запуск: разрешить VPN-профиль, вставить
   тестовую ссылку `vless://`, Import, Connect. Проверить IP на 2ip.ru.
9. Логи туннеля — Console.app, фильтр «VlessPacketTunnel»; уровень логов
   Xray меняется в `xrayConfig()` (`"loglevel": "debug"`).

## Важно

- Ничего не переписывай архитектурно — только точечные правки имён API.
- `go mod tidy` тянет модули при первой сборке — нужна сеть.
- Без платного Apple Developer-аккаунта соберётся под симулятор (проверка
  компиляции), но на реальный iPhone 6 с iOS 12 поставит только подпись
  платного аккаунта (либо джейлбрейк-обход подписи типа AppSync).
- Результат запушь в `main`.
