# Figma Claude / MCP skill club — Smart map

Source of truth for official trees: [figma/mcp-server-guide](https://github.com/figma/mcp-server-guide) (see also `FIGMA-SKILLS-VENDOR.md`).

## Layers

```
User intent
    → figma-designer (Smart orchestrator)     ← this pack
        → mandatory official skill for the tool
            → Figma MCP tools (use_figma, get_design_context, …)
                → Plugin API / REST behind MCP
```

## Official skills (full club)

| Skill | Role | Tool gate | Fleet v1 |
|---|---|---|---|
| **figma-use** | Plugin API rules + references (gotchas, d.ts, WWDS) | Before every `use_figma` | **YES** |
| **figma-generate-design** | Multi-section screens from DS (code or description) | With `use_figma` for composed views | **YES** |
| **figma-create-new-file** | planKey + drafts file | Before every `create_new_file` | **YES** |
| **figma-design-to-code** | Design → code workflow | Before `get_design_context` for implementation | optional later |
| **figma-generate-library** | Tokens + component library from code | Long phased `use_figma` | optional |
| **figma-code-connect** | Map Figma ↔ code components | Code Connect tools | optional |
| **figma-generate-diagram** | Mermaid / NL → FigJam | Before `generate_diagram` | optional |
| **figma-use-figjam** | FigJam node APIs | FigJam `use_figma` | optional |
| **figma-use-slides** | Slides APIs | Slides `use_figma` | optional |
| **figma-use-motion** / **figma-implement-motion** | Motion | Motion tools | optional |
| **figma-swiftui** | SwiftUI-oriented codegen | design-to-code variant | optional |

Community skills (audit-design-system, apply-design-system, …) are **not** fleet-installed; do not assume they exist.

## MCP tools Smart agents actually use

| Tool | Typical skill |
|---|---|
| `use_figma` | figma-use (+ generate-design / generate-library) |
| `get_screenshot` / `get_metadata` | any canvas path |
| `get_libraries` / `search_design_system` | generate-design discovery |
| `create_new_file` | figma-create-new-file |
| `get_design_context` / `get_variable_defs` | figma-design-to-code |
| `generate_figma_design` | parallel capture with generate-design (web apps + images) |
| `generate_diagram` | figma-generate-diagram |
| `whoami` | planKey for create_new_file |

## Directions

- **→ canvas (write):** generate-design / use / create-new-file / generate-library  
- **← code (read design):** design-to-code + `get_design_context`  
- Do not mix directions in one confused loop without saying which side is source of truth.
