# Changelog

## [1.5.0](https://github.com/Shir0o/Budget/compare/v1.4.0...v1.5.0) (2026-11-28)


### Features

* **mcp:** retag_line changes a Reviewed line's business status ([#37](https://github.com/Shir0o/Budget/issues/37)) ([9f610ff](https://github.com/Shir0o/Budget/commit/9f610ffb3aa0582918a13f7f6216ef491a20d95f))
* **mcp:** split_line splits a line into parts on request ([#40](https://github.com/Shir0o/Budget/issues/40)) ([c220790](https://github.com/Shir0o/Budget/commit/c220790d3978768bdbc6088a43b17faabf060035))


### Bug Fixes

* **mcp:** run one budget call at a time per Worker isolate ([#39](https://github.com/Shir0o/Budget/issues/39)) ([bb141df](https://github.com/Shir0o/Budget/commit/bb141dfce5d1f5e0610d03d3d52abf0f2b0e345a))

## [1.4.0](https://github.com/Shir0o/Budget/compare/v1.3.0...v1.4.0) (2026-11-28)


### Features

* **import:** bring Actual lines in Reviewed in every year ([#31](https://github.com/Shir0o/Budget/issues/31)) ([6e81d5b](https://github.com/Shir0o/Budget/commit/6e81d5b175c68a95cbec08fbee78b4117227fc03))
* **mcp:** add mark_imported_reviewed to clear an old import from Review ([#32](https://github.com/Shir0o/Budget/issues/32)) ([9de8147](https://github.com/Shir0o/Budget/commit/9de8147ce8e522d490e57de070e26e0dd43d3646))


### Bug Fixes

* **mcp:** amount edits, clearer no-change message, line counts in Review summary ([#35](https://github.com/Shir0o/Budget/issues/35)) ([ece2257](https://github.com/Shir0o/Budget/commit/ece225734561482c26fce1fc0add0a90da678f9d))
* **migration:** name budget Categories and accounts in YNAB differences ([#36](https://github.com/Shir0o/Budget/issues/36)) ([f3c17aa](https://github.com/Shir0o/Budget/commit/f3c17aafc31b113dfe8def325973e94b4e5fe50e))
* **simplefin:** ask for 90 days counting today, not 91 ([#29](https://github.com/Shir0o/Budget/issues/29)) ([03987e4](https://github.com/Shir0o/Budget/commit/03987e473cfc32697224faceaa67c1e768ae312d))

## [1.3.0](https://github.com/Shir0o/Budget/compare/v1.2.0...v1.3.0) (2026-11-28)


### Features

* **import:** make new Business Tags from Actual tags and skip number-only #tags ([#27](https://github.com/Shir0o/Budget/issues/27)) ([a141daf](https://github.com/Shir0o/Budget/commit/a141daf71ffb8bba77b44e4c20900cb2314f89a6))

## [1.2.0](https://github.com/Shir0o/Budget/compare/v1.1.4...v1.2.0) (2026-11-28)


### Features

* **app:** add the Treemap app icon ([#25](https://github.com/Shir0o/Budget/issues/25)) ([3cab21e](https://github.com/Shir0o/Budget/commit/3cab21e2f9b60ce4b6d9daba278efbe12003650c))

## [1.1.4](https://github.com/Shir0o/Budget/compare/v1.1.3...v1.1.4) (2026-11-28)


### Bug Fixes

* **import:** start a new budget from an Actual import ([#23](https://github.com/Shir0o/Budget/issues/23)) ([7c317e0](https://github.com/Shir0o/Budget/commit/7c317e06261f6d64896442d94d637f5b29871669))

## [1.1.3](https://github.com/Shir0o/Budget/compare/v1.1.2...v1.1.3) (2026-11-28)


### Bug Fixes

* **mcp:** omit form-action CSP directive on /authorize ([#20](https://github.com/Shir0o/Budget/issues/20)) ([ea0647e](https://github.com/Shir0o/Budget/commit/ea0647ec897e680c67300a6759ed152e3162c901))
* **sync:** keep subfolder listings in the app data space ([#22](https://github.com/Shir0o/Budget/issues/22)) ([99fcc7d](https://github.com/Shir0o/Budget/commit/99fcc7ddd10b2e6a39892d2113ad62b149790261))

## [1.1.2](https://github.com/Shir0o/Budget/compare/v1.1.1...v1.1.2) (2026-11-27)


### Bug Fixes

* **ui:** fix settings row alignment and small-screen overflow ([#18](https://github.com/Shir0o/Budget/issues/18)) ([b124834](https://github.com/Shir0o/Budget/commit/b1248346f03e9bdd9c988ab12e4b11dbf7d6069c))

## [1.1.1](https://github.com/Shir0o/Budget/compare/v1.1.0...v1.1.1) (2026-11-27)


### Bug Fixes

* **android:** upgrade AGP to 9.1.1 and Gradle to 9.5.0 ([#16](https://github.com/Shir0o/Budget/issues/16)) ([6e23690](https://github.com/Shir0o/Budget/commit/6e23690445b1219d1f7cbeb68e42405d6128783c))

## [1.1.0](https://github.com/Shir0o/Budget/compare/v1.0.6...v1.1.0) (2026-11-27)


### Features

* **mcp:** optional cloud MCP server as one more sync device ([#9](https://github.com/Shir0o/Budget/issues/9)) ([92aab78](https://github.com/Shir0o/Budget/commit/92aab7879c0a46518f3d7f8a342971a95055004a))
* propose and link bank-imported transfers ([#3](https://github.com/Shir0o/Budget/issues/3)) ([#6](https://github.com/Shir0o/Budget/issues/6)) ([c6c61fd](https://github.com/Shir0o/Budget/commit/c6c61fdd85e1d6a66533ce24c0bf3661a7ba381d))
* **sync:** connect Google Drive on Android and the Mac ([#10](https://github.com/Shir0o/Budget/issues/10)) ([33c53b9](https://github.com/Shir0o/Budget/commit/33c53b9277bf54ae8e42ec7c492ed5aa55dedce3))

## [1.0.6](https://github.com/Shir0o/budget/compare/v1.0.5...v1.0.6) (2026-11-21)


### Bug Fixes

* **ui:** clarify segmented control selected and unselected states ([#106](https://github.com/Shir0o/budget/issues/106)) ([8511130](https://github.com/Shir0o/budget/commit/85111305299c236235af630ea810096777e9e228))

## [1.0.5](https://github.com/Shir0o/budget/compare/v1.0.4...v1.0.5) (2026-11-14)


### Bug Fixes

* **ui:** adapt category action buttons and tap targets ([#102](https://github.com/Shir0o/budget/issues/102)) ([486b654](https://github.com/Shir0o/budget/commit/486b654292034fdb03d10cc7a04fc98e993780e7))

## [1.0.4](https://github.com/Shir0o/budget/compare/v1.0.3...v1.0.4) (2026-11-13)


### Bug Fixes

* **ui:** adapt category row and available pill scaling ([#99](https://github.com/Shir0o/budget/issues/99)) ([ef7df33](https://github.com/Shir0o/budget/commit/ef7df33c476f2e93a45991d2de9e3efaf0537c2a))

## [1.0.3](https://github.com/Shir0o/budget/compare/v1.0.2...v1.0.3) (2026-11-11)


### Bug Fixes

* **macos:** use the login keychain so the app can start ([#93](https://github.com/Shir0o/budget/issues/93)) ([e6c9526](https://github.com/Shir0o/budget/commit/e6c9526114522100a895f8766b13e472ad494f0e))
* **ui:** improve responsive layout and nav badge scaling ([#95](https://github.com/Shir0o/budget/issues/95)) ([d7bca98](https://github.com/Shir0o/budget/commit/d7bca98310ffa46984c465519357e1a9c2ee3afd))
