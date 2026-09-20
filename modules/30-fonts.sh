#!/bin/bash
# Stage 30: MesloLGS Nerd Font (v3) downloading and caching.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# Source helper libraries
# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

OS="${OS:-$(detect_os)}"
DRY_RUN="${DRY_RUN:-false}"

if [ "$OS" = "macos" ]; then
    FONT_DIR="$HOME/Library/Fonts"
else
    FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
fi

echo "  Installing MesloLGS Nerd Font (v3) fonts into $FONT_DIR..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Downloading MesloLGS Nerd Font v3 (Regular, Bold, Italic, Bold Italic) to $FONT_DIR"
else
    mkdir -p "$FONT_DIR"
    CACHE_DIR="${HOME_SETTINGS_FONT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/home-settings/fonts}"
    mkdir -p "$CACHE_DIR"
    BASE_FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/v3.3.0/patched-fonts/Meslo/S"
    FONT_SPECS=(
        "Regular/MesloLGSNerdFont-Regular.ttf|MesloLGSNerdFont-Regular.ttf|MesloLGS NF Regular.ttf"
        "Bold/MesloLGSNerdFont-Bold.ttf|MesloLGSNerdFont-Bold.ttf|MesloLGS NF Bold.ttf"
        "Italic/MesloLGSNerdFont-Italic.ttf|MesloLGSNerdFont-Italic.ttf|MesloLGS NF Italic.ttf"
        "Bold-Italic/MesloLGSNerdFont-BoldItalic.ttf|MesloLGSNerdFont-BoldItalic.ttf|MesloLGS NF Bold Italic.ttf"
    )
    pids=()
    for spec in "${FONT_SPECS[@]}"; do
        IFS='|' read -r remote_rel v3_font _ <<< "$spec"
        target="$FONT_DIR/$v3_font"
        cached="$CACHE_DIR/$v3_font"
        if [ ! -s "$target" ]; then
            if [ -s "$cached" ]; then
                cp "$cached" "$target"
            else
                (
                    tmp_file="$cached.tmp.$$.${BASHPID:-$RANDOM}"
                    trap 'rm -f "$tmp_file"' EXIT
                    if curl -fsSL "$BASE_FONT_URL/$remote_rel" -o "$tmp_file"; then
                        mv -f "$tmp_file" "$cached" && cp "$cached" "$target"
                    else
                        rm -f "$tmp_file"
                        exit 1
                    fi
                ) &
                pids+=($!)
            fi
        elif [ ! -s "$cached" ]; then
            cp -f "$target" "$cached"
        fi
    done
    if [ ${#pids[@]} -gt 0 ]; then
        download_failed=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                download_failed=1
            fi
        done
        if [ "$download_failed" -ne 0 ]; then
            exit 1
        fi
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$FONT_DIR" "${FONT_SPECS[@]}" << 'PYEOF'
import array, os, struct, sys

def calc_checksum(b):
    pad = (4 - (len(b) % 4)) % 4
    if pad:
        b = b + b"\x00" * pad
    arr = array.array("I", b)
    if sys.byteorder == "little":
        arr.byteswap()
    return sum(arr) & 0xFFFFFFFF

def patch_ttf(data, rename_to_nf=False):
    if len(data) < 1024:
        return data
    try:
        num_tables = struct.unpack(">H", data[4:6])[0]
        tables = {}
        for i in range(num_tables):
            off = 12 + i * 16
            tag = data[off:off+4].decode("latin1")
            t_off, t_len = struct.unpack(">II", data[off+8:off+16])
            tables[tag] = (i, t_off, t_len)
        for req in ("OS/2", "cmap", "loca", "glyf", "hmtx", "name", "head"):
            if req not in tables:
                return data
    except Exception:
        return data

    buf = bytearray(data)

    # 1. Calibrate OS/2 vertical metrics to match romkatv/powerlevel10k-media MesloLGS NF 1:1
    #    Clears USE_TYPO_METRICS (bit 7) and sets sTypoAscender=1556, sTypoDescender=-492, sTypoLineGap=0
    _, os2_off, _ = tables["OS/2"]
    fs_sel = struct.unpack(">H", buf[os2_off+62:os2_off+64])[0]
    struct.pack_into(">H", buf, os2_off+62, fs_sel & ~0x0080)
    struct.pack_into(">hhh", buf, os2_off+68, 1556, -492, 0)

    # 2. Transplant romkatv's hand-calibrated U+E0B0..U+E0B3 Powerline glyph contours and bearings
    #    so shelf endcaps (U+E0B0/U+E0B2) and thin chevrons (U+E0B1/U+E0B3) bleed seamlessly into Base02.
    _, cmap_off, _ = tables["cmap"]
    num_sub = struct.unpack(">H", buf[cmap_off+2:cmap_off+4])[0]
    cmap = {}
    for i in range(num_sub):
        pid, eid, sub_off = struct.unpack(">HHI", buf[cmap_off+4+i*8:cmap_off+12+i*8])
        f_off = cmap_off + sub_off
        if struct.unpack(">H", buf[f_off:f_off+2])[0] == 12:
            n_groups = struct.unpack(">I", buf[f_off+12:f_off+16])[0]
            for g in range(n_groups):
                sc, ec, sg = struct.unpack(">III", buf[f_off+16+g*12:f_off+28+g*12])
                for cp in (0xE0B0, 0xE0B1, 0xE0B2, 0xE0B3):
                    if sc <= cp <= ec:
                        cmap[cp] = sg + (cp - sc)

    _, loca_off, _ = tables["loca"]
    _, glyf_off, _ = tables["glyf"]
    _, hmtx_off, _ = tables["hmtx"]

    romk_patches = {
        0xE0B0: (bytes.fromhex("0001ffdbfd7e04d0080c000200000309012504f5fb0b080bfabbfab9"), bytes.fromhex("04d1ffdc")),
        0xE0B1: (bytes.fromhex("0001fff3fd9204dd07f8000500000337090127010c6c047cfb846c0416078771facefacc7204c200"), bytes.fromhex("04d1fff4")),
        0xE0B2: (bytes.fromhex("00010000fd7e04f5080c00020000090204f5fb0b04f5fd7f05470545"), bytes.fromhex("04d10000")),
        0xE0B3: (bytes.fromhex("0001fff3fd9204dd07f800050000130107090117c304196afb82047e6a02c6fb3e72053405327100"), bytes.fromhex("04d1fff4")),
    }

    for cp, (g_bytes, hm_bytes) in romk_patches.items():
        gid = cmap.get(cp)
        if gid is not None:
            g1, g2 = struct.unpack(">II", buf[loca_off+gid*4:loca_off+gid*4+8])
            slot_len = g2 - g1
            if len(g_bytes) <= slot_len:
                buf[glyf_off+g1:glyf_off+g2] = g_bytes + b"\x00" * (slot_len - len(g_bytes))
                buf[hmtx_off+gid*4:hmtx_off+gid*4+4] = hm_bytes

    # 3. Optionally rebuild OpenType name table for native 'MesloLGS NF' (MesloLGS-NF-*) family lookup
    if rename_to_nf:
        t_idx, n_off, _ = tables["name"]
        fmt, count, str_off = struct.unpack(">HHH", buf[n_off:n_off+6])
        records = []
        pool = bytearray()
        for i in range(count):
            r_off = n_off + 6 + i * 12
            pid, eid, lid, nid, slen, soff = struct.unpack(">HHHHHH", buf[r_off:r_off+12])
            raw = bytes(buf[n_off+str_off+soff:n_off+str_off+soff+slen])
            try:
                enc = "utf-16-be" if pid in (0, 3) else "mac_roman"
                s = raw.decode(enc)
                s = s.replace("MesloLGS Nerd Font", "MesloLGS NF").replace("MesloLGSNF-", "MesloLGS-NF-")
                raw = s.encode(enc)
            except Exception:
                pass
            records.append((pid, eid, lid, nid, len(raw), len(pool)))
            pool.extend(raw)
        new_name = bytearray(struct.pack(">HHH", fmt, count, 6 + count * 12))
        for rec in records:
            new_name.extend(struct.pack(">HHHHHH", *rec))
        new_name.extend(pool)
        while len(new_name) % 4 != 0:
            new_name.append(0)
        while len(buf) % 4 != 0:
            buf.append(0)
        new_off = len(buf)
        buf.extend(new_name)
        tables["name"] = (t_idx, new_off, len(new_name))
        struct.pack_into(">II", buf, 12 + t_idx * 16 + 8, new_off, len(new_name))

    for tag in ("OS/2", "glyf", "hmtx", "name"):
        t_idx, t_off, t_len = tables[tag]
        cs = calc_checksum(bytes(buf[t_off:t_off+t_len]))
        struct.pack_into(">I", buf, 12 + t_idx * 16 + 4, cs)

    _, head_off, head_len = tables["head"]
    struct.pack_into(">I", buf, head_off + 8, 0)
    head_cs = calc_checksum(bytes(buf[head_off:head_off+head_len]))
    struct.pack_into(">I", buf, 12 + tables["head"][0] * 16 + 4, head_cs)
    total_cs = calc_checksum(bytes(buf))
    struct.pack_into(">I", buf, head_off + 8, (0xB1B0AFBA - total_cs) & 0xFFFFFFFF)
    return bytes(buf)

font_dir = sys.argv[1]
for spec in sys.argv[2:]:
    _, v3_font, legacy_font = spec.split("|")
    v3_path = os.path.join(font_dir, v3_font)
    legacy_path = os.path.join(font_dir, legacy_font)
    if not os.path.isfile(v3_path):
        continue
    with open(v3_path, "rb") as f:
        raw = f.read()
    patched_v3 = patch_ttf(raw, rename_to_nf=False)
    patched_nf = patch_ttf(raw, rename_to_nf=True)
    for target_path, payload in ((v3_path, patched_v3), (legacy_path, patched_nf)):
        if os.path.isfile(target_path):
            try:
                with open(target_path, "rb") as existing:
                    if existing.read() == payload:
                        continue
            except Exception:
                pass
        tmp_path = f"{target_path}.tmp.{os.getpid()}"
        with open(tmp_path, "wb") as out:
            out.write(payload)
        try:
            os.unlink(target_path)
        except FileNotFoundError:
            pass
        os.replace(tmp_path, target_path)
PYEOF
    else
        for spec in "${FONT_SPECS[@]}"; do
            IFS='|' read -r _ v3_font legacy_font <<< "$spec"
            v3_target="$FONT_DIR/$v3_font"
            legacy_target="$FONT_DIR/$legacy_font"
            if [ -s "$v3_target" ]; then
                rm -f "$legacy_target"
                cp "$v3_target" "$legacy_target"
            fi
        done
    fi
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
fi
