#!/usr/bin/env bash
# Install (symlink) mods from this repo's mods/ directory into AoM:R's local mods folder.
#
# Default behavior: symlink each mods/<NAME>/ into <MODS_DIR>/<NAME> so that
# edits in the repo are immediately picked up by the game on next launch.
#
# Usage:
#   ./install-mods.sh              # symlink all mods/*/ (skip pre-existing real dirs)
#   ./install-mods.sh --copy       # copy contents instead of symlinking
#   ./install-mods.sh --force      # replace existing entries (real dirs OR stale symlinks)
#   ./install-mods.sh --uninstall  # remove only symlinks pointing back at this repo
#   ./install-mods.sh --list       # show what's currently installed
#   ./install-mods.sh --mods-dir <path>   # override autodetected MODS_DIR
#
# Environment overrides:
#   MODS_DIR  Full path to mods/local/. If unset, the script tries to find it under
#             ~/.local/share/Steam or ~/.steam/steam for Steam app id 1934680.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/mods"
APPID=1934680

MODE=symlink
FORCE=0
ACTION=install

while [[ $# -gt 0 ]]; do
    case "$1" in
        --copy)       MODE=copy ;;
        --force)      FORCE=1 ;;
        --uninstall)  ACTION=uninstall ;;
        --list)       ACTION=list ;;
        --mods-dir)   MODS_DIR="$2"; shift ;;
        -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Autodetect MODS_DIR if not provided.
if [[ -z "${MODS_DIR:-}" ]]; then
    for steam_root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
        prefix="$steam_root/steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold"
        [[ -d "$prefix" ]] || continue
        # User-id subfolder (Steam ID, e.g. 76561198343472988). Pick the first/only.
        for user_dir in "$prefix"/*/; do
            [[ -d "${user_dir}mods/local" ]] || continue
            MODS_DIR="${user_dir}mods/local"
            break 2
        done
    done
fi

if [[ -z "${MODS_DIR:-}" ]]; then
    echo "Could not autodetect MODS_DIR. Pass --mods-dir <path> or set MODS_DIR env var." >&2
    echo "Expected something like: ~/.local/share/Steam/steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold/<steam-id>/mods/local" >&2
    exit 1
fi

mkdir -p "$MODS_DIR"

# Resolve canonical paths so symlink-target comparisons are reliable.
SRC_DIR_REAL="$(readlink -f "$SRC_DIR")"

list_mods() {
    printf '%-30s %-10s %s\n' "MOD" "STATE" "TARGET"
    for entry in "$MODS_DIR"/*/; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ -L "${entry%/}" ]]; then
            target="$(readlink -f "${entry%/}")"
            if [[ "$target" == "$SRC_DIR_REAL"/* ]]; then
                printf '%-30s %-10s %s\n' "$name" "symlink↑" "$target"
            else
                printf '%-30s %-10s %s\n' "$name" "symlink" "$target"
            fi
        else
            printf '%-30s %-10s %s\n' "$name" "dir" "(real directory)"
        fi
    done
}

if [[ "$ACTION" == "list" ]]; then
    echo "MODS_DIR: $MODS_DIR"
    list_mods
    exit 0
fi

if [[ "$ACTION" == "uninstall" ]]; then
    removed=0
    for entry in "$MODS_DIR"/*/; do
        [[ -L "${entry%/}" ]] || continue
        target="$(readlink -f "${entry%/}")"
        if [[ "$target" == "$SRC_DIR_REAL"/* ]]; then
            rm "${entry%/}"
            echo "removed symlink: $(basename "$entry")"
            removed=$((removed + 1))
        fi
    done
    echo "Removed $removed symlink(s) that pointed at this repo. Real directories untouched."
    exit 0
fi

# install
if [[ ! -d "$SRC_DIR" ]]; then
    echo "No mods/ directory in repo at $SRC_DIR — nothing to install." >&2
    exit 0
fi

shopt -s nullglob
mods=("$SRC_DIR"/*/)
if [[ ${#mods[@]} -eq 0 ]]; then
    echo "No mods found under $SRC_DIR/."
    exit 0
fi

echo "MODS_DIR: $MODS_DIR"
if [[ "$FORCE" -eq 1 ]]; then
    echo "Mode: $MODE (force)"
else
    echo "Mode: $MODE"
fi
echo

for mod_path in "${mods[@]}"; do
    name="$(basename "${mod_path%/}")"
    src="$(readlink -f "${mod_path%/}")"
    dst="$MODS_DIR/$name"

    if [[ -e "$dst" || -L "$dst" ]]; then
        if [[ -L "$dst" ]]; then
            existing="$(readlink -f "$dst")"
            if [[ "$existing" == "$src" ]]; then
                echo "✓ $name already symlinked correctly — skipping"
                continue
            fi
        fi
        if [[ "$FORCE" -ne 1 ]]; then
            echo "⚠ $name exists at destination (use --force to replace) — skipping"
            continue
        fi
        rm -rf "$dst"
    fi

    if [[ "$MODE" == "symlink" ]]; then
        ln -s "$src" "$dst"
        echo "→ $name symlinked"
    else
        cp -r "$src" "$dst"
        echo "→ $name copied"
    fi
done
