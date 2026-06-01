# Inter font files for OG image generation

Файли `Inter-Regular.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf` потрібні Satori
(всередині Next.js `ImageResponse`) для рендеру `/opengraph-image`. Satori
не має вбудованого шрифта — кожен виклик мусить передати TTF/OTF з повним
набором гліфів (Latin + Cyrillic у нашому випадку).

Префікс `_og-fonts/` (з підкреслення) сигналізує Next.js не route'ити цей
каталог як сторінку (App Router конвенція для приватних каталогів).

## Джерело

Inter v4.0 — https://github.com/rsms/inter/releases/tag/v4.0
`extras/ttf/Inter-{Regular,SemiBold,Bold}.ttf` з офіційного release zip.

## Ліцензія

Inter поширюється під **SIL Open Font License 1.1** © The Inter Project Authors.
Повний текст ліцензії: https://github.com/rsms/inter/blob/master/LICENSE.txt

OFL дозволяє bundling у комерційні/некомерційні продукти без royalty,
вимагаючи зберігати attribution і не продавати font як standalone.
