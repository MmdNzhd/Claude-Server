# Club product — live design kit (Smart)

Extracted **2026-07-26** via Figma MCP (`mcp-via-xray` → `https://mcp.figma.com/mcp`) from the real Club file. Prefer this over inventing Inter/Material defaults.

## File anchors

| Field | Value |
|---|---|
| File name | Club 1.2 - Design |
| `fileKey` | `YR4B9skUnJe50tnfCyRwYo` |
| Setting page | `1:4394` (PAGE name **Setting**) |
| Example URL | `https://www.figma.com/design/YR4B9skUnJe50tnfCyRwYo/Club-1.2---Design?node-id=1-4394` |
| Designer project (server mount) | `club` / Cursor project `home-tarane-mounts-club` |

Parse `node-id=1-4394` → `1:4394`. Stay on this `fileKey` unless the user switches files.

## What to harvest (industry checklist → Club)

Before mutating Club UI, agents must know:

1. **Libraries + `libraryKey`** (not just names)
2. **Components / sets + `componentKey`** for Button, Text Field, Tab, Dialog, Empty State, etc.
3. **Variables** — color schemes, spacing, radius, typography string tokens
4. **Text / effect styles** — Typography/* scale
5. **Fonts actually used on the page** (critical — Club is NOT Inter)
6. **Page / frame map** for the task
7. **MCP / seat / missing-font limits** (see below)

## Libraries

| Name | Role | `libraryKey` |
|---|---|---|
| **Design Kit V.2** | Primary DS (team) — use this | `lk-6e46e0aaea5d394bb3d1a9f6cab094ad78f6d1e88036afba707992630c372398ba461782acce2ad876e4d8ec7e4bf2323e3f5e9766787153a03acf4ef8bf6996` |
| Smarties | Secondary / legacy overlap (few components) | prefer Design Kit V.2 when both exist |
| Design Review | Rare | ignore unless user asks |
| Material 3 Design Kit | Available to add — **do not** default to it for Club | — |

`get_libraries` on this file lists Design Kit V.2 under `libraries_added_to_file`.

## Fonts (do not guess Inter)

From `use_figma` walk of PAGE `Setting` (`1:4394`):

| Font | Approx. usage on Setting |
|---|---|
| **IRANYekanXFaNum** Regular / Medium / DemiBold | Dominant (~1600+ segments) |
| IRANYekanXFaNum Bold / ExtraBold | Rare |
| IRANYekanXVF DemiBold | Rare |
| Montserrat Bold / SemiBold | Secondary Latin |
| Roboto Medium / Regular | Sparse |
| Poppins / SF Pro Display / Inter | Noise — do not adopt as product default |

Typography variables in Design Kit V.2 (string tokens, collection **Typography**):

- `Typescale/Display {Large,Medium,Small}/Font`
- `Typescale/Headline Large/Font`
- `Typescale/Title {Large,Medium,Small}/Font`
- `Typescale/Body {Large,Medium,Small,XSmall}/Font`
- `Typescale/Lable {Large,Medium,Small}/Font` (kit spelling: **Lable**)

Text styles observed via search: `Typography/Body/*`, `Typography/Display/*`, `Typography/Headline/Small`, `Typography/Lable/*`, `Typography/Title/*`, plus `Header 1` / `Header 2`.

### Missing-font blocker (MCP) — cannot fix from Linux server

Golden MCP runtime reports **`hasMissingFont: true`** on almost all `IRANYekanXFaNum` text (~1669 nodes on Setting). Plugin API **cannot mutate `characters` / restyle text** until the font is available to that runtime (or the node is rewritten with a loaded font — usually wrong for Club).

**Live probe (2026-07-26):** `listAvailableFontsAsync` ≈ 8927 fonts; **zero** `IRANYekan*` / `Yekan*`.  
`loadFontAsync({ family: "IRANYekanXFaNum", style: "Regular" })` → family does not exist.  
MCP cloud does **not** see fonts merely installed on the laptop/desktop (Figma forum + this probe). Local `IRANYekan*FaNum.ttf` (old family, not **X**) on Smart app trees also do **not** match `IRANYekanXFaNum`.

| Attempt | Works for MCP? |
|---|---|
| Install TTF on Windows/Linux for golden user | **No** |
| Figma desktop “Installed by you” | **No** (UI only) |
| Upload **IRANYekanXFaNum** as **org/team shared font** (Org/Enterprise admin) | **Yes** (required path) |
| Swap text to Inter to edit | **Forbidden** for Club product |

**Admin runbook (font) — human with license + Figma admin:**

1. Obtain licensed **IRANYekanXFaNum** files (Regular / Medium / DemiBold at minimum) — family name must be exactly `IRANYekanXFaNum`.
2. Figma plan must support shared fonts (Organization/Enterprise). Team-only local fonts are not enough for MCP.
3. Org admin: Admin → Resources → Fonts → Upload (or team admin → team fonts).  
   Docs: [Upload custom fonts to an organization](https://help.figma.com/hc/en-us/articles/360039956774-Upload-custom-fonts-to-an-organization)
4. Re-test via MCP: `loadFontAsync` + clear `hasMissingFont` on a Setting label.
5. Until then: edit currency copy in **Figma desktop** as a human, or accept MCP read-only for text.

**Agent rule:** If `hasMissingFont` is true, stop and point at this runbook. Do not silently swap to Inter.

## Seat / auth limits (golden MCP account)

`whoami` (golden): `aligholizade1995@gmail.com`.

| Team | Seat | Impact |
|---|---|---|
| **smartfigma's team** | **Dev** (pro) | Design = view/comment → MCP **read-only mode** |
| Several other personal teams | Full | Not the Club owner team |

Live probe: `importComponentSetByKeyAsync(Button)` → **Can't call in read-only mode**.  
Dev seat blocks canvas writes via MCP even after fonts are fixed.

**Admin runbook (seat) — do this in Figma UI:**

1. Sign in as **admin** of **smartfigma's team**.
2. Members → find **`aligholizade1995@gmail.com`** (hamed aligholizade).
3. Change seat **Dev → Full**.
4. Confirm MCP `whoami` shows `"seat": "Full"` for that team.
5. Smoke-test a tiny `use_figma` rename; if still read-only, fix file share to **can edit**.

Alternative: wire MCP OAuth from a Full designer account into `/etc/claude-code/figma-mcp.env` + `sync-cursor-mcp` (policy permitting).

REST `api.figma.com/v1/...` with the MCP `figu_` token returns **403 Invalid scope** — inventory must use **Figma MCP tools**, not REST.

## Tokens (variables) — prefer binding over hex

Examples from Design Kit V.2 search (not exhaustive):

**Spacing:** `Spacing/4` … `Spacing/80`, `Spacing/None`  
**Radius:** `Sahpe Radius/{None,xxsm,xsm,sm,md,lg,xlg,xxlg,Full}` (kit spelling: **Sahpe**) + `Shape Radius`  
**Schemes / brand:** `Schemes/Primary`, `Schemes/On Primary`, `Schemes/Primary Container`, …  
**Palettes:** `Pallettes/Brand Source color/Primary|Accent|Error/…` (kit spelling: **Pallettes**)  
**Opacity:** `Opacity color/Drak-*`, `Opacity color/Light-*` (kit spelling: **Drak**)

Effect / color styles include `Smart-theme/key-colors/*`, `Smart-theme/ref/primary/*`, `Primary-Main`, `Shadow-Button-Defult`, `Card`.

## Core components (prefer Design Kit V.2 keys)

Import via `importComponentByKeyAsync` / `importComponentSetByKeyAsync` using `componentKey`.

| Name | Type | componentKey |
|---|---|---|
| Button | component_set | `458d35071e85449dbbb9dd3a84d2b3b7f590bc86` |
| Text Field | component_set | `854aa5f03814fd73dc62aeb6ec078094700cf4ee` (live Setting; search also `bcd7fd6a220a3ea999857d22bbc521a4161ef494`) |
| Icon Button | component_set | `d944b6c03135555209bcfe39706be51cbe8dbe7a` |
| Fab Button | component_set | `3b3a218418e47ad4e2c0fb1f4ab565d3b0fd8ff3` |
| Check Box | component | `5a99431b7db95bcc4c3d1a97c238d74aa473821b` |
| Radio Button | component | `7ad60e5982ac354c0b95655ca076bee1042169ee` |
| Switch | component_set | `4b45e42fc11b1a8356abce99f3fd714fd2f8f260` |
| Tab | component_set | `cf39dfc48857612153e8ddc41c2422d5cf5d8808` |
| Mobile Tab | component | `3ce6e5b247d7f4212f9308b1a6e76b81f20cc208` |
| Bottom Nav | component_set | `52aa3fe414c0d51351c185c25f4271780fa2e98b` |
| Card | component_set | `ebce4e8c88b17d1ac741ae85ab21edf6dbaf1789` (live Setting; search also `37c289cc1f9f53f208934ce1617019c0e748a023`) |
| Empty State | component_set | `0e910fc81684d39195bce0aed5ee5689c3dfb0a4` |
| Dialogue Elements | component_set | `370ebc9c773977dc3fe2ae4e8ba7d79fe282b544` |
| Loading | component | `cc41848b5096b192bca868008e01984dd08bdab1` |
| Badges | component_set | `7ba8af1b339e89883f49614fb7d2308a33fadb3e` |
| List | component_set | `320c25389ff70b3834c1457d4e19137f3844748b` |
| Pagination Item | component_set | `70fc6ae81ebe1db56678713a75e09367f4631b46` |
| Tooltip | component_set | `ec78a7a5fd13fdf1e09ef9c91c2a723628ba09d3` |
| chip | component_set | `efc5f756d58808c91f5bec6bf0b714574b640b64` |
| currency | component | `d68ad6815ffca5222d1c0dd52b0998764828c058` |
| setting | component | `371786e761aa70b6d5003f7d55a11a51deeecefa` |
| Branch-Outline / Bold / Bulk | component | icons for branch UI |

Full extract counted **~108** unique component keys across searches (98 Design Kit V.2, 9 Smarties). Re-run `search_design_system` when a needed part is missing from this table.

## Currency copy task (ریال → تومان)

Common Tarane ask on Setting / branch general settings:

- Many TEXT nodes are exactly `ریال` (labels) or include `ریال` in amounts like `15,000,000 ریال`.
- Some UI already says `تومان` (segment / helper copy).
- Exact label node IDs seen on Setting (all `IRANYekanXFaNum`, **`hasMissingFont: true`**):

`60:4012`, `110:9348`, `98:6096`, `31:6235`, `31:6271`, `49:5773`, `49:5890`, `43:3308`, `43:3281`, `43:3459`, `43:3466`, `43:3802`, `44:4522`, `48:4768`, `48:4770`, `48:4783`, `48:4795`, `48:4808`, `67:12066`, `105:9834`, `106:11300`, `101:6900`, `71:13143`, `110:8666`, `103:8105`, `105:9992`, `103:7820`, `105:9300`

**Workflow:**

1. Load `figma-designer` + this kit + `figma-use`.
2. `use_figma`: set current page to Setting; for each target id, if `!hasMissingFont`, `loadFontAsync` → set `characters` to `تومان` (or rewrite amount suffix). Return mutated IDs.
3. If `hasMissingFont` → **stop** with the font/seat message (do not fake Inter).
4. Screenshot the branch settings frame the user cares about.

## MCP tool notes for Club

| Tool | Club notes |
|---|---|
| `get_metadata` | Works with `fileKey` + `nodeId` (good structure dump) |
| `get_libraries` / `search_design_system` | Works; scope queries to Design Kit V.2 |
| `use_figma` | Works for inventory + mutations when seat/font allow |
| `get_design_context` / `get_variable_defs` | May error *“nothing selected”* without desktop selection — fall back to `get_metadata` + `use_figma` |
| REST API | Out of scope for golden `figu_` token |

## File pages (complete map)

This Club file currently has **2** pages only:

| nodeId | name | top-level children |
|---|---|---|
| `0:1` | 🔥 Thumbnail | 1 |
| `1:4394` | Setting | 2 |

## Live Setting harvest (use_figma, 2026-07-26 deep)

PAGE `1:4394` **Setting** stats:

| Metric | Value |
|---|---|
| TEXT nodes | 1674 |
| TEXT with `hasMissingFont` | 1669 |
| INSTANCE nodes | 1610 |
| Unique instance main keys | 75 |
| Frames/sections/components walked | 3938 |

### Search key vs live instance key (critical)

`search_design_system` returns **library publish keys**. Instances on the page may bind a **different key** (variant set revision / nested main). For mutate/swap on Setting, prefer keys from the live table below.


| Widget | Key in earlier search inventory | Key actually instanced on Setting | Prefer for edits on this page |
|---|---|---|---|
| Button | `458d35071e85449dbbb9dd3a84d2b3b7f590bc86` | `458d35071e85449dbbb9dd3a84d2b3b7f590bc86` | same |
| Text Field | `bcd7fd6a220a3ea999857d22bbc521a4161ef494` | `854aa5f03814fd73dc62aeb6ec078094700cf4ee` | **live instance key** |
| Card | `37c289cc1f9f53f208934ce1617019c0e748a023` | `ebce4e8c88b17d1ac741ae85ab21edf6dbaf1789` | **live instance key** |
| Content | `51b0e28884917fa4a19831fa9c018fcec67846b2` | `008d1616a015493e2297aad63e844d46029340c6` | **live instance key** |
| Nav Item - Drawer | `17e79d1e623d8e36a587bb3f3ff16ccffd98470f` | `703d5c9d5e941f8ca677be6469cf48dbc4dd1252` | **live instance key** |
| Switch | `4b45e42fc11b1a8356abce99f3fd714fd2f8f260` | `4b45e42fc11b1a8356abce99f3fd714fd2f8f260` | same |
| chip | `efc5f756d58808c91f5bec6bf0b714574b640b64` | `efc5f756d58808c91f5bec6bf0b714574b640b64` | same |


### Top instances on Setting (live keys — prefer these)

| Name | Type | key (from instance main/set) | count |
|---|---|---|---|
| Nav Item - Drawer | set | `703d5c9d5e941f8ca677be6469cf48dbc4dd1252` | 154 |
| Content | set | `008d1616a015493e2297aad63e844d46029340c6` | 154 |
| Text Field | set | `854aa5f03814fd73dc62aeb6ec078094700cf4ee` | 125 |
| Button | set | `458d35071e85449dbbb9dd3a84d2b3b7f590bc86` | 88 |
| add-outline | component | `48452a98a8242e83061c979139aae2e4e364ba73` | 80 |
| chip | set | `efc5f756d58808c91f5bec6bf0b714574b640b64` | 70 |
| arrow-up | component | `402063b79a11774cd98d7b476f07aa512b1185ec` | 66 |
| Check Box Sign | set | `2300422fadc621599121f4550fb673950de6e5a8` | 45 |
| User | set | `5e04089e7e1e04decd0fdf3d5d1883c7d90556f6` | 42 |
| arrow-left | set | `31906b12130e1747aa7eb2a2782604fdf9e28125` | 32 |
| Switch | set | `4b45e42fc11b1a8356abce99f3fd714fd2f8f260` | 28 |
| Drop Down Cell | set | `5a5277e0425c7b59cb7c536eb501a74caf34f510` | 28 |
| arrow-left-sm | component | `98bebba804bba3882e7e878f7306e762511ef2fb` | 26 |
| Status Indicator | set | `453374231170fa274a7eae8f43ea204e07790c82` | 24 |
| tick-square | set | `6069e665e0ac6f15c8006619b9b091c284e3897b` | 24 |
| notification | set | `9c7b67fe02942b5b8190a591cffc9d3177251239` | 22 |
| home-2 | set | `f3ffe4ef02e1fc03482b74d8a8af6da55bb5fd2c` | 22 |
| profile-2user | set | `2067165a709e647375e419c9b9baff494b0d0297` | 22 |
| medal-star | set | `e46059c4db9b69cc8128334da9859e74aaf169f9` | 22 |
| clipboard-text | set | `98be92df9f35a43f254be02857d54acde97db64a` | 22 |
| arrow-up | component | `91eeaa5a3eaf1fde1d05bccb94c541ae2dd32509` | 22 |
| setting-2-bulk | component | `076e1129e8242410ec30d7cce62ee19dee009332` | 22 |
| sms | set | `52f8d77eab2712e80381db160d7a3ba238d56c55` | 22 |
| user-tag | set | `0657d624a681ba77c624483e80b888249675445c` | 22 |
| send | set | `f02f5e27c7c2c9ba832a39563749abbb9eb85111` | 22 |
| Top app bar | set | `43d19aec13f6a9fa9e7ee51d9f0b8fbe0723d091` | 22 |
| .Building Blocks/status-bar | component | `06605581cb4ff1b74d9ae75bbe983d8f8322d6f6` | 22 |
| location | set | `f1d8231fba0aeab56727e97930e60212737c15f1` | 20 |
| Radio Button Sign | set | `7ecb5b1a5d28a609a5d33792f075b556a98dee5c` | 20 |
| notification | set | `65583b836b63009d0c1592a4b9f2db4e85e48a66` | 20 |
| menu | set | `cdbd6060a39529071409559f87e085e6baff9cc6` | 20 |
| Card | set | `ebce4e8c88b17d1ac741ae85ab21edf6dbaf1789` | 20 |
| arrow-left | component | `ff7bff2d6337e54bb4a1ce3b016b9bcfde28a0b6` | 20 |
| location | set | `08bf8d634a9cd52f76e702f238ccf34bf96a4b65` | 20 |
| clock | set | `f34ddd5fdaeb1dbf36cd1f3d1a25174f9c562319` | 20 |
| Icon Button | set | `d944b6c03135555209bcfe39706be51cbe8dbe7a` | 14 |
| arrow-up | component | `4751eafbb1ff9c82cca39c7ae13e22bb5a59d53e` | 13 |
| vuesax/bulk/link-circle | component | `2e9483048091ef75b4e357984c376022649201cd` | 11 |
| Check Box | component | `5a99431b7db95bcc4c3d1a97c238d74aa473821b` | 11 |
| Blank | set | `a9d9a7eac35d24fae92caf31dc009ae6c9bd5300` | 11 |

### Variants / component properties

Sampled from Setting instances (not exhaustive). Agents must re-read `componentProperties` / `variantProperties` at runtime before `setProperties`.

Examples seen: `Status Indicator` variant `State=Approve`; icon sets `Property 1=bulk`.

Button `importComponentSetByKeyAsync` probe: **failed** — `Error: in importComponentSetByKeyAsync: Can't call "importComponentSetByKeyAsync" in read-only mode`  
→ golden MCP session is **read-only** on this file (Dev seat / read-only mode). Creating or importing components is blocked until Full + write access.

### Currency (reconfirmed)

| | |
|---|---|
| Currency-related TEXT | 37 |
| Exact `ریال` | 28 |
| Exact `تومان` | 2 |
| Currency nodes with missing font | 36 |

Exact `ریال` ids: `60:4012`, `110:9348`, `98:6096`, `31:6235`, `31:6271`, `49:5773`, `49:5890`, `43:3308`, `43:3281`, `43:3459`, `43:3466`, `43:3802`, `44:4522`, `48:4768`, `48:4770`, `48:4783`, `48:4795`, `48:4808`, `67:12066`, `105:9834`, `106:11300`, `101:6900`, `71:13143`, `110:8666`, `103:8105`, `105:9992`, `103:7820`, `105:9300`

## Completeness limits (honest)

| Area | Status |
|---|---|
| File access + library name/key | Done |
| Empirical font on Setting | Done (`IRANYekanXFaNum`) |
| Core + live top instance keys | Done (this section) — still not every icon key in Design Kit V.2 |
| Full library variable export | **Not done** (MCP search is query-scoped) |
| Typography variable resolved values | **Not in file locals** — use fontUsage / bound vars on nodes |
| Variant/property definitions serialized | **Not done** — re-import/read at runtime when write allowed |
| MCP text edit ریال→تومان | **Blocked** (missing font + read-only) |
| Other product screens beyond Setting | N/A — file only has Thumbnail + Setting today |

## Agent checklist (Club / Tarane)

- [ ] Same `fileKey` `YR4B9skUnJe50tnfCyRwYo`
- [ ] Primary library **Design Kit V.2** (keys above)
- [ ] Product font **IRANYekanXFaNum** — never default Inter
- [ ] Bind Spacing / Sahpe Radius / Schemes variables when present
- [ ] Checked `hasMissingFont` + smartfigma **Dev** seat before promising edits
- [ ] Screenshot after each section
