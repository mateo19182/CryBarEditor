# AoM:R Modding — Agent Playbook

Concrete recipes for creating Age of Mythology: Retold mods on this Linux/Proton setup. Tools and paths are pre-resolved; recipes are ordered roughly by complexity. Prefer **additive mods** over file replacement — they survive game patches and don't conflict with other mods.

The upstream prose docs are in `Documentation/Modding.md`. This file is the operational checklist.

## Resolved paths (this machine)

| What | Path |
|---|---|
| Steam app id | `1934680` |
| Game install | `/home/m19182/.local/share/Steam/steamapps/common/Age of Mythology Retold/` |
| Game tree root (`<GAME_ROOT>`) | `<install>/game/` |
| Main archive | `<GAME_ROOT>/data/Data.bar` |
| Reference PDFs | `<install>/BANG_Documentation/` |
| Local mods folder (`<MODS_DIR>`) | `~/.local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold/76561198343472988/mods/local/` |
| `CryBar.Cli` (`$CRYBAR`) | `/home/m19182/Work/personal/CryBarEditor/CryBar.Cli/bin/Release/net10.0/CryBar.Cli.dll` |

Set once per shell:
```bash
export CRYBAR=/home/m19182/Work/personal/CryBarEditor/CryBar.Cli/bin/Release/net10.0/CryBar.Cli.dll
export GAME_ROOT="/home/m19182/.local/share/Steam/steamapps/common/Age of Mythology Retold/game"
export MODS_DIR="$HOME/.local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold/76561198343472988/mods/local"
```

If `dotnet` or the CLI is missing, rebuild from `/home/m19182/Work/personal/CryBarEditor/`:
```bash
dotnet build CryBar.Cli/CryBar.Cli.csproj -c Release
```

## Mod folder rules (read this once)

1. **No manifest required.** AoM:R scans `mods/local/<MOD_NAME>/` and overrides files at matching relative paths. There is no `Mod.json` or `modinfo.xml`. Verified against subscribed Workshop mods.
2. **Path mirroring is relative to `<GAME_ROOT>`** (i.e. `game/`). Files inside BAR archives are virtually placed under the BAR's parent directory. So an entry `strings/English/string_table.txt` inside `<GAME_ROOT>/data/Data.bar` maps to mod path `<MOD_DIR>/data/strings/English/stringmods.txt`.
3. **Additive over replacement.** Use `*_mods.xml` / `stringmods.txt` whenever possible. Full-file replacement breaks on game patches.
4. **Mod folder name** becomes the in-game label. Avoid spaces and special chars. Use `kebab-case`.

### Additive file map

| Base entry | Additive override | Root XML element |
|---|---|---|
| `proto.xml` | `proto_mods.xml` | `<protomods>` |
| `techtree.xml` | `techtree_mods.xml` | `<techtreemods>` |
| `powers.xml` | `powers_mods.xml` | `<powersmod>` |
| `proto_unit_commands.xml` | `proto_unit_command_mods.xml` | `<protounitcommandsmods>` |
| `abilities.xml` | `abilities_mods.xml` | `<abilitiesmods>` |
| `major_gods.xml` | `major_gods_mods.xml` | `<civsmods>` |
| `string_table.txt` | `stringmods.txt` | (key=value, no XML) |

Merge modes (`mergeMode="..."` attribute on tags inside additive XML):
- `modify` (default) — replace if present, else add
- `replace` — overwrite existing only
- `remove` — delete existing tag
- `add` — append, never replace

## CryBar.Cli quick reference

```bash
dotnet $CRYBAR --help                                              # subcommands: bar, convert, compress, decompress, deps, search, root
dotnet $CRYBAR root set "$GAME_ROOT"                               # one-time, persisted
dotnet $CRYBAR bar info <archive>                                  # entry count, sizes, file types
dotnet $CRYBAR bar list <archive> [--filter <glob>]                # list entries
dotnet $CRYBAR bar export <archive> <entry> [-o <dir>] [--convert] # extract; --convert does XMB→XML, DDT→TGA
dotnet $CRYBAR convert <file>                                      # XMB↔XML, etc.
dotnet $CRYBAR search "<query>"                                    # search across root + BARs
```

`--quiet` suppresses chrome and is preferred when piping to grep. `--json` for structured output.

The `Data.bar` archive holds protos (`*.xmb`), string tables (`strings/<lang>/string_table.txt`), and AI scripts (`*.xs`). Other BARs (e.g. `UIResources.bar`, `Art*.bar`) hold UI icons, textures, models. Use `bar info`/`list` to discover.

## Recipe 1 — String rename (simplest, ~2 minutes)

Use case: rename units, civs, techs, tooltips. Pure text edit, no XMB conversion.

```bash
# 1. Find the IDs you want to override
mkdir -p /tmp/aomr-extract
dotnet $CRYBAR bar export "$GAME_ROOT/data/Data.bar" "strings/English/string_table.txt" -o /tmp/aomr-extract --quiet
grep "STR_UNIT_HOPLITE" /tmp/aomr-extract/strings/English/string_table.txt

# 2. Create mod folder + stringmods.txt
MOD=my-renames
mkdir -p "$MODS_DIR/$MOD/data/strings/English"
cat > "$MODS_DIR/$MOD/data/strings/English/stringmods.txt" <<'EOF'
ID = "STR_UNIT_HOPLITE_NAME"   ;   Str = "Spartan Hoplite"
ID = "STR_UNIT_TOXOTES_NAME"   ;   Str = "Cretan Toxotes"
EOF
```

Mirror to other languages by repeating in the appropriate `strings/<Language>/` subfolder. Folder names use TitleCase (e.g. `English`, `French`, `PortugueseBrazil`).

## Recipe 2 — Unit balance / new units (proto_mods.xml)

Use case: change unit stats, build limits, costs; clone existing units; remove units.

```bash
# 1. Extract proto.xml (it's stored as proto.xml.XMB; --convert decodes to XML)
dotnet $CRYBAR bar export "$GAME_ROOT/data/Data.bar" "proto.xml.XMB" -o /tmp/aomr-extract --convert --quiet
# Result: /tmp/aomr-extract/proto.xml — read it to find <unit name="..."> tags

# 2. Author proto_mods.xml at mod path data/proto_mods.xml
MOD=my-balance
mkdir -p "$MODS_DIR/$MOD/data"
cat > "$MODS_DIR/$MOD/data/proto_mods.xml" <<'EOF'
<protomods>
  <!-- Buff Hoplite HP: replace just the <hitpoints> child -->
  <unit name="Hoplite">
    <hitpoints mergeMode="replace">120</hitpoints>
  </unit>

  <!-- Add a new variant cloned from Hoplite -->
  <unit name="EliteHoplite" mergeMode="add">
    <displaynameid>STR_UNIT_ELITE_HOPLITE_NAME</displaynameid>
    <icon>resources\greek\player_color\units\hoplite_icon.png</icon>
    <!-- ...rest of attributes copied from Hoplite with deltas... -->
  </unit>

  <!-- Remove an obsolete unit entirely -->
  <unit mergeMode="remove" name="OldUnit" />
</protomods>
EOF
```

Notes:
- New string IDs introduced here (e.g. `STR_UNIT_ELITE_HOPLITE_NAME`) must be defined in a sibling `stringmods.txt`.
- Backslashes in `<icon>` paths are correct — that's the in-game format.
- `proto.xml` is the largest file in the game; use `grep -n "<unit name=\""` on the extracted copy to find anchors.

## Recipe 3 — God powers (XMB-only files)

`*.godpowers`, `*.abilities`, `*.tactics` are stored *only* as XMB. Even though `bar export --convert` produces an XML view, the **mod file must be XMB**. Edit the XML, then convert back.

```bash
# Extract greek god powers as editable XML
dotnet $CRYBAR bar export "$GAME_ROOT/data/Data.bar" "greek.godpowers.XMB" -o /tmp/aomr-extract --convert --quiet
# Edit /tmp/aomr-extract/greek.godpowers (now XML)
# Convert back to XMB
dotnet $CRYBAR convert /tmp/aomr-extract/greek.godpowers
# Drop the resulting .XMB into mod path data/greek.godpowers.XMB
```

For `powers.xml`, use the additive method (`powers_mods.xml`, plain XML, root `<powersmod>`) instead — much simpler.

## Recipe 4 — DDT textures and PNG icons

```bash
# UI icon replacement (PNG, no conversion)
dotnet $CRYBAR bar list "$GAME_ROOT/data/UIResources.bar" --filter "*hoplite*"
dotnet $CRYBAR bar export "$GAME_ROOT/data/UIResources.bar" "<entry-path>" -o /tmp/aomr-extract --quiet
# Replace with same-resolution PNG, drop into mod at the same relative path

# DDT texture (use Avalonia GUI for "Replace and export DDT" — preserves mipmaps and DDT params).
# CLI conversion DDT↔TGA exists via `convert`, but full DDT replacement is GUI-driven.
```

## Recipe 5 — Custom unit sound

`game/sound/<your-mod-name>/clip.wav` plus a `.soundset` file referencing it, plus a unit soundset XML pointing the unit's `Select`/`Attack`/etc. soundtypes at your soundset name. See `Documentation/Modding.md` for the XML schemas.

## Verification & debugging

1. **Enable in game:** Main Menu → Mods → Local → toggle `<MOD_NAME>` on → restart.
2. **Inspect merged data:** add `DebugOutputGameData` to `<GAME_ROOT>/config/user.cfg` (create it if absent). After launching the game, processed files appear under the prefix's `users/steamuser/AppData/Local/Temp/Age of Mythology Retold/Data/`. Useful for confirming an additive override actually merged.
3. **Mod failed to appear in menu:** check the mod folder is directly under `mods/local/` (not nested), and that file paths under it mirror `<GAME_ROOT>/...`.
4. **String didn't change:** confirm you placed `stringmods.txt` in the language folder matching your active game language (each is a separate file).
5. **proto_mods.xml didn't apply:** the loader is silent on XML errors — run with `DebugOutputGameData` and diff the merged `proto.xml` against base.

## Common pitfalls

- Putting `stringmods.txt` at `data/stringmods.txt` instead of `data/strings/English/stringmods.txt`. The path must mirror the BAR-internal location.
- Editing `*.XMB` files as XML and dropping them into the mod folder without converting back. The game expects compiled XMB for those entries.
- Adding new units in `proto_mods.xml` without also defining their string IDs in `stringmods.txt` — units appear with raw `STR_...` placeholders.
- Mod folder names with spaces or non-ASCII characters — sometimes silently ignored.
- Editing files inside `mods/subscribed/` — those get overwritten on Workshop sync. Always work in `mods/local/`.

## Worked example (already on disk)

`tier1-rename-test` exists in `mods/local/` as a minimal end-to-end example: a single `data/strings/English/stringmods.txt` that renames Hoplite/Hypaspist/Toxotes. Use it as a template for new string mods.
