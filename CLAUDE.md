# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Zotero 8/9 plugin: sends PDF attachments to the official MinerU API, saves parsed Markdown back into Zotero as stored attachments, and optionally drives an OpenAI-compatible chat API for AI summaries and AI translation of the parsed Markdown.

Upstream: https://github.com/lisontowind/zotero-mineru (this checkout is a personal fork; planned divergence includes a full Chinese → English conversion).

## Build

```bash
bash build-xpi.sh
```

Reads `manifest.json` → produces `zotero-mineru-<version>.xpi` via `bsdtar --format zip`. The XPI's file list is hard-coded in `build-xpi.sh` (`FILES=...`); if a new top-level asset needs to ship, add it there. No tests, no linter, no Node toolchain — reload by re-installing the rebuilt XPI in Zotero.

## Release workflow

GitHub Actions `release.yml` fires on `v*` tags and validates that the tag matches `manifest.json`. Correct manual order:

1. Bump `"version"` in [manifest.json](manifest.json).
2. Optional local sanity build with `bash build-xpi.sh`.
3. Commit and `git push origin main`.
4. `git tag vX.Y.Z` (exact match with `manifest.json`).
5. `git push origin vX.Y.Z`.

The workflow rebuilds the XPI as `zotero-mineru.xpi`, rewrites [updates.json](updates.json), and only commits it back to `main` if the content actually changed.

**Intentional divergence:** [.github/workflows/release.yml](.github/workflows/release.yml) hard-codes `strict_max_version: '8.0.*'` in the rewritten `updates.json`, while [manifest.json](manifest.json) declares `9.0.*`. Auto-updates therefore only flow to Zotero 8.x clients; 9.x users install via direct XPI. Don't "fix" without confirming intent.

## Architecture pointers

- **Load chain**: [bootstrap.js](bootstrap.js) registers the prefs pane (3-tier fallback for cross-build compatibility), `loadSubScript`s [mineru.js](mineru.js), then `ZoteroMineru.init` → `addToAllWindows` → `main`. Shutdown reverses all of it.
- **Singleton style**: everything lives on one object literal `ZoteroMineru = { ... }` in [mineru.js](mineru.js). No classes, no modules. Per-window state held only in `popupListeners: new WeakMap()`.
- **Context menu — dual registration**: same menu definitions ([mineru.js:39](mineru.js:39) `getContextMenuDefinitions()`) registered twice: modern `Zotero.MenuManager.registerMenu` ([mineru.js:84](mineru.js:84)) when available; XUL `createXULElement("menu")` + `popupshowing` listener fallback ([mineru.js:135](mineru.js:135)) for older builds. Always edit the definitions list, not the registration sites.
- **Preferences**: branch `extensions.zotero-mineru.*`, defaults in [prefs.js](prefs.js), UI in [preferences.xhtml](preferences.xhtml) + [preferences.js](preferences.js). `apiToken` has a legacy `apiKey` fallback on read — preserve it. `summaryRequestJSON` / `translateRequestJSON` are user-editable JSON merged into chat-completions payloads via `mergeRequestPayload`; `model` and `messages` are reserved.
- **Localization**: FTL covers only the five menu labels ([locale/en-US/zotero-mineru.ftl](locale/en-US/zotero-mineru.ftl), [locale/zh-CN/zotero-mineru.ftl](locale/zh-CN/zotero-mineru.ftl)). All other UI strings (alerts, progress text, errors, summary system prompt) are hardcoded in [mineru.js](mineru.js) and [preferences.js](preferences.js) and are English in this fork. The `zh-CN` FTL and [README.zh-CN.md](README.zh-CN.md) are intentionally left from upstream — do not remove without confirming.
- **Pipelines worth knowing**: PDF parse with phased progress reporting in `parseAttachmentWithMineru` ([mineru.js:549](mineru.js:549)); ZIP download with a 4-strategy URL/auth fallback in `downloadParseResultZip` ([mineru.js:708](mineru.js:708)); Markdown→HTML with 5-engine Zotero-builtin fallback then `convertMarkdownToBasicHTML` ([mineru.js:1126](mineru.js:1126)); translation chunking + bounded-concurrency workers + per-chunk retry + user-confirmed failed-chunk retry rounds in `handleTranslateCommand` / `translateChunksWithConcurrency` ([mineru.js:2950](mineru.js:2950), [mineru.js:3185](mineru.js:3185)).

## Tag-driven state

Tags drive both UI visibility (`getTasks` predicates) and dedup. Don't introduce parallel state.

| Tag | Attached to | Role |
|-----|-------------|------|
| `#MinerU-Parse` | Markdown attachment (current) or note (legacy) | Marks parsed source; readable by all three downstream commands |
| `#MinerU-Parsed` | Parent regular item | Marks "parsed already" |
| `#MinerU-Summary` | Note | Dedup for `collectSummaryTasks` |
| `#MinerU-Translation` | Markdown attachment | Dedup for `collectTranslateTasks` |

## Design decisions that look like bugs

- **Translation image links point at the source attachment's storage** (`../<sourceKey>/images/...`). Translation attachments depend on the source `#MinerU-Parse` attachment surviving. This avoids duplicating image bytes and is deliberate — don't "fix" by copying images into the translation's own storage unless the user explicitly opts in.
- **`summaryLanguage === "English"`** branches `callLLMForSummary` to a hand-tuned English system prompt template; any other value uses the generic template that interpolates the target language string. The default for `summaryLanguage` and `translateLanguage` is `"English"` ([prefs.js](prefs.js)). Users can type any language name into the free-text input in the preferences pane.
- **`pickMarkdownEntry`** prefers a `.md` whose stem equals the PDF stem, then any non-`_layout.md`, then entry 0.
- **Error messages from `parseAttachmentWithMineru` are wrapped** by `wrapErrorWithParseStatus` to embed the current phase — preserve this when refactoring error handling.
- **`withTimeout`-wrapped errors** carry `name === "TimeoutError"` / `code === "ETIMEDOUT"`; `isTimeoutError` checks them and `formatUserFacingError` appends a tuning hint specifically on timeouts.

## File-style quirks

- Tabs for indent.
- Semicolons inconsistent: the older code uses them; the newer translation / markdown-attachment section (roughly [mineru.js:1959](mineru.js:1959) onward) mostly omits them. Match the local function's style rather than enforcing one globally.
- `Zotero.debug("Zotero MinerU: ...")` is the only log channel.
- No third-party dependencies — everything is platform (`fetch`, `IOUtils`, `PathUtils`, `Components.classes[...]`, `Services.scriptloader`, `Zotero.Prefs`, `Zotero.Attachments`).

## Documentation maintenance

When the menu structure, preference keys, parse / translation flow, tag system, storage layout, release process, or user-visible behavior changes, update **this file** in the same change. README-only updates are insufficient.
