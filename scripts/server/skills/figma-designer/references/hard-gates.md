# Hard gates (from official Figma Claude club)

Violating these is why canvas work feels "slow" and broken. Enforce them.

## Tool / skill gates

| Gate | Rule |
|---|---|
| G1 | No `use_figma` until **`figma-use`** is loaded |
| G2 | No `create_new_file` until **`figma-create-new-file`** is loaded |
| G3 | Composed screens → also load **`figma-generate-design`** |
| G4 | Design→code → load **`figma-design-to-code`** before `get_design_context` when installed |
| G5 | On tool error → STOP; read message; fix; then retry (scripts are atomic) |

## Discovery before mutate (generate-design)

| Gate | Rule |
|---|---|
| D1 | Forbidden: `search_design_system` until existing-screen harvest attempted or logged N/A |
| D2 | Forbidden: mutating `use_figma` until component/variable/style checklist for needed parts is filled |
| D3 | Forbidden: building sections as top-level orphans then `appendChild` into wrapper across calls |
| D4 | Wrapper created first; sections built **inside** it by ID |

## Plugin API (use-figma)

| Gate | Rule |
|---|---|
| P1 | Font load before any text-affecting mutate |
| P2 | ≤1 `setCurrentPageAsync` per `use_figma` call |
| P3 | `HUG`/`FILL` only after node is in auto-layout parent (when required) |
| P4 | Always `return` created/mutated IDs |
| P5 | No `figma.notify`, no `closePlugin`, no bare `console.log` as output |
| P6 | Variable `scopes` set explicitly when creating variables |

## Beta / product limits (set expectations)

- ~20kb response per `use_figma` call → keep scripts small
- Custom fonts / some assets limited — prefer DS components
- Output may need human polish; screenshot loop is mandatory quality bar

## Club product gates (Smart / Tarane)

| Gate | Rule |
|---|---|
| C1 | Club `fileKey` `YR4B9skUnJe50tnfCyRwYo` → load `club-design-kit.md` before mutate |
| C2 | Primary library **Design Kit V.2** — do not default to Material 3 / Inter |
| C3 | Product font **IRANYekanXFaNum** — never restyle Club UI to Inter to "make MCP happy" |
| C4 | If `hasMissingFont` on target text → stop; ask for font on golden MCP / manual desktop edit |
| C5 | Golden account on **smartfigma's team** is often **Dev** — Full seat required for many creates |
| C5b | If `use_figma` says **read-only mode**, do not promise creates/imports/swaps — inventory only |
| C7 | Prefer **live instance keys** from the page over `search_design_system` keys when they differ |
| C6 | Prefer MCP `get_metadata` / `use_figma` / `search_design_system`; REST with `figu_` is scope-blocked |
