# Canvas workflows for Smart designers

Adapted from official `figma-generate-design` + `figma-use` for **description-first** work (requirements lists, not only code→Figma).

## A. New screen from requirements

1. Confirm Design file URL (`figma.com/design/...`).
2. Restate sections in a short checklist; confirm with user if ambiguous.
3. **Discover** (no mutate yet):
   - Find a nearby existing screen → harvest INSTANCE keys + variable/style usage.
   - Else `get_libraries` → `search_design_system` with synonyms (button, input, card, nav, modal, empty, …).
   - Record component property keys for text overrides.
4. Create **wrapper** auto-layout (own `use_figma`), return `wrapperId`, place to the right of existing content.
5. For each section:
   - Import keys with `Promise.all`
   - Build section auto-layout; bind variables
   - Instance components; `setProperties` for labels
   - `wrapper.appendChild(section)` then `layoutSizingHorizontal = 'FILL'`
   - `get_screenshot` on section; fix issues before next section
6. Final `get_screenshot` on wrapper; list created node IDs for the user.

## B. Edit selection

1. Node URL required.
2. `get_metadata` + `get_screenshot` on selection.
3. Small `use_figma`: load fonts if text; mutate; return `mutatedNodeIds`.
4. Re-screenshot; stop on error (atomic).

## C. Empty state / add-on block

Same as A but append under an existing parent frame ID (discover parent first). Prefer DS empty-state / illustration components if present.

## D. New file then design

1. `figma-create-new-file` (`whoami` → `planKey` if needed).
2. Reuse returned `file_key` for all later calls.
3. Continue with A (note: empty file → discovery may skip 2a-ii; document N/A and use `search_design_system` / libraries).

## What to import vs build

| Build manually | Import from DS |
|---|---|
| Page/modal wrapper | Buttons, inputs, cards, nav, tabs |
| Section frames / layout scaffolding | Color / spacing / radius variables |
| | Text + effect styles |

Never reconstruct icons from rotated primitives — instance icon components or `createNodeFromSvg` with real SVG.

## Validation checklist (per section)

- No placeholder "Title" / "Button" left
- No clipped text / overlaps
- Correct variant (e.g. Primary not Neutral)
- Font family matches existing product screens in the file
- Variables bound (not raw hex) when DS has them
