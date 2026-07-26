---
name: figma-designer
description: >-
  Smart fleet orchestrator for the Figma Claude/MCP skill club. Use whenever
  anyone pastes a figma.com URL or asks to build/edit UI in Figma (page from
  requirements, edit selection, empty state, settings screen), OR to implement
  a Figma frame as code. Loads first; then forces the correct official skill
  chain (figma-use, figma-generate-design, figma-create-new-file,
  figma-design-to-code when present). Prefer this over ad-hoc MCP calls.
disable-model-invocation: false
---

# Smart Figma Designer — fleet orchestrator

This is the **Smart/Sepidz private skill**. It does **not** replace official
Figma skills — it **routes and hard-gates** them so designers (e.g. Tarane) and
devs get the new Figma Claude club workflow without memorizing it.

Official trees live beside this skill under `~/.cursor/skills/`. Deep playbooks:
`references/skill-map.md`, `references/canvas-workflows.md`,
`references/hard-gates.md`.

**Club / Tarane product file:** always load
`references/club-design-kit.md` when the URL/`fileKey` is Club
(`YR4B9skUnJe50tnfCyRwYo`), the mount/project is `club`, or the user says
Club / کلاب / شعبه settings. That kit is a **live MCP extract** (fonts,
Design Kit V.2 keys, currency nodes, seat/font blockers) — do not invent
Inter/Material defaults for Club.

## 0. Fleet reality (do not invent setup)

- Figma MCP is already wired: `mcp-via-xray` → `https://mcp.figma.com/mcp` + golden `figu_` bearer (`sync-cursor-mcp`).
- If MCP tools are missing: stop → admin `sudo claude-server sync-cursor-mcp` → **Reload Window**. Docs: `docs/cursor-mcp-pack.md`.
- Writes need **Full** seat + **edit** on the file. Dev seat = read-only outside drafts.
- `/add-plugin figma` is optional enrichment. Do **not** block if fleet skills exist under `~/.cursor/skills/`.

## 1. Intent router (pick ONE primary path)

| User intent (any language) | Direction | Load / follow |
|---|---|---|
| Build page/screen/modal from **requirements / description / bullets** | **→ canvas** | This skill + **`figma-generate-design`** + always **`figma-use`** before every `use_figma` |
| Edit selection / tweak copy / move / restyle node | **→ canvas** | **`figma-use`** (mandatory) |
| New blank Design / FigJam / Slides file | **→ canvas** | **`figma-create-new-file`** then hand off |
| Build / sync **library components / tokens** from code | **→ canvas** | **`figma-generate-library`** if installed; else say missing + use `figma-use` carefully |
| FigJam diagram / whiteboard | FigJam | **`figma-use-figjam`** / **`figma-generate-diagram`** if installed |
| Implement Figma as **code in the repo** | **canvas → code** | **`figma-design-to-code`** if installed; else `get_design_context` with its rules (see `references/skill-map.md`) |
| Ambiguous | — | Ask once: *write inside Figma* vs *implement in code*? |

**Never call `use_figma` without loading `figma-use` first.**  
**Never call `create_new_file` without loading `figma-create-new-file` first.**  
**Never call `get_design_context` for design→code without `figma-design-to-code` when that skill is installed.**

Pass `skillNames` on tool calls (logging): e.g. `figma-use`, or `figma-use,figma-generate-design`. If loaded as MCP resource, prefix `resource:`.

If Figma tools are deferred: batch-load schemas once (`ToolSearch` `select:use_figma,get_screenshot,get_metadata,search_design_system,get_libraries,create_new_file,get_design_context`).

## 2. URL / fileKey contract

1. Require `figma.com/design|board|slides/...` file or node URL (or `fileKey` + `nodeId`). If missing → ask once.
2. Parse editor from URL: `/design/` = Design, `/board/` = FigJam, `/slides/` = Slides. Do not use Design-only APIs on FigJam/Slides.
3. Node URL preferred for edits (`node-id=` → convert `-` to `:`).
4. Keep working in the **same** `fileKey` for the whole conversation unless the user switches files.

## 3. Designer path: requirements → canvas (default for Smart designers)

Follow official **`figma-generate-design`** end-to-end. Adapt Step 1 for **description-only** (no codebase):

1. **Understand deliverable** — list sections + UI parts (header, form, table, CTA…). Infer product font from existing screens in the file (do **not** default to Inter if the file uses something else). For **Club**, product font is **IRANYekanXFaNum** (see `club-design-kit.md`).
2. **Discover DS before any mutate** (hard gates — see `references/hard-gates.md`):
   - **Club:** start from `references/club-design-kit.md` (Design Kit V.2 `libraryKey` + **live Setting instance keys**). Prefer live keys over `search_design_system` when they differ. Re-check with `use_figma` walk / targeted search.
   - Else: prefer walking an **existing screen** in the file for component keys / variables / text+effect styles.
   - Then `get_libraries` → scoped `search_design_system` (last resort).
   - Fill a component map including TEXT/BOOLEAN/VARIANT property keys.
   - Before text edits: check `hasMissingFont` and golden seat on the file's team (Club: smartfigma often **Dev** + missing IRANYekan on MCP).
3. **Wrapper first** — one `use_figma`: create auto-layout wrapper off `(0,0)`, return `wrapperId`. Never build sections as orphans then reparent.
4. **One section per `use_figma`** — append inside wrapper; `FILL`/`HUG` only **after** `appendChild`; bind variables (no hex/px when tokens exist); override instance text via `setProperties`, not raw `characters` when props exist.
5. **Screenshot after each section** + full wrapper at end. Fix cropped text, overlaps, placeholder labels, wrong variants.
6. On `use_figma` error → **STOP** (atomic). Fix script. Do not blind-retry.

Canonical prompts (designer-facing):

```
Using this Figma file: <URL>
Build a new settings screen with auto layout using our existing components.
Requirements:
- …
Do not invent a new design system; reuse library components and variables.
```

```
Using this selection: <NODE_URL>
Change the primary button label to "Save"; keep components/variables.
```

```
Using this Figma file: <URL>
Add an empty state below the list that matches the existing design system.
```

```
Club file: https://www.figma.com/design/YR4B9skUnJe50tnfCyRwYo/Club-1.2---Design?node-id=1-4394
On Setting / branch general settings, change currency labels from ریال to تومان.
Use Design Kit V.2 + IRANYekanXFaNum; load figma-designer club-design-kit.
If hasMissingFont or Dev seat blocks writes, stop and report — do not swap fonts.
```

## 4. Critical Plugin API rules (must not skip — full detail in `figma-use`)

Distilled from the official club; agents still MUST load `figma-use` + grep `references/` when writing scripts:

1. `return` only output channel; no `figma.closePlugin`, no IIFE wrapper, no `figma.notify`.
2. Colors `0–1`; clone fills/strokes before mutate.
3. Text: **load font → await → mutate → return IDs** (use node's current fonts via `getStyledTextSegments`).
4. Pages: `await figma.setCurrentPageAsync` only; context resets every call; **≤1 page switch per call** (parallelize multi-page).
5. Auto-layout: related children → `createAutoLayout`; `layoutSizing*` vs `*AxisSizingMode` enums differ.
6. Return **all** `createdNodeIds` / `mutatedNodeIds`.
7. Design systems: start from `figma-use/references/working-with-design-systems/wwds.md`.
8. Prefer `node.query(...)`, `createAutoLayout`, `importComponentSetByKeyAsync`, `setBoundVariable*`.

## 5. Design → code path (devs)

If user wants code from Figma:

1. Load **`figma-design-to-code`** when present under `~/.cursor/skills/`.
2. `get_design_context` first — not screenshot-only.
3. Treat React+Tailwind output as **reference**; adapt to project stack; reuse project components/tokens.
4. Honor hint priority: Code Connect → docs links → annotations → tokens → raw hex.
5. Assets: use MCP asset URLs; do not invent SVG icons.

## 6. Anti-patterns (Smart)

- Drawing rectangles with hardcoded hex instead of DS instances/variables.
- One-shot entire product in a single `use_figma`.
- Calling `use_figma` / `create_new_file` / `get_design_context` without the matching mandatory skill.
- Guessing layout from chat with no file URL.
- Telling the user to re-run `/add-plugin figma` when fleet skills already exist (unless tools truly missing).
- Using Visual Copilot / Builder as the default — out of scope for this skill unless the user explicitly asks.

## 7. Done checklist

- [ ] Correct official skill(s) loaded
- [ ] Same `fileKey`; editor type respected
- [ ] DS discovery completed before mutate (canvas path)
- [ ] Section screenshots clean; IDs returned
- [ ] User told how to open/review the file in Figma
