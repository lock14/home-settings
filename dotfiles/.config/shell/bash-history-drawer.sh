# Zero-Dependency Inline `Ctrl+r` Interactive History Drawer for Bash (Bash 3.2+ compatible)
# Renders a live-themed viewport with smart-case, ^/$/! token matching, UTF-8/CJK truncation,
# SIGWINCH resize handling, bracketed paste, and Bash 3.2 Readline macro fallback.

_hs_bash_utf8_pop_char() {
    local s="${1:-}" len b ch
    len="${#s}"
    [ "$len" -eq 0 ] && { REPLY=""; return 0; }
    local LC_ALL=C
    len="${#s}"
    local cut=1
    while [ "$cut" -lt "$len" ] && [ "$cut" -lt 4 ]; do
        ch="${s:len-cut:1}"
        printf -v b '%d' "'$ch"
        if [ "$b" -ge 128 ] && [ "$b" -le 191 ]; then
            cut=$((cut + 1))
        else
            break
        fi
    done
    REPLY="${s:0:len-cut}"
}

_hs_bash_hist_build_index() {
    local mode="${1:-fast}"
    if [ -z "$(builtin history 1)" ]; then
        return 0
    fi
    if [ "$mode" = "full" ]; then
        builtin fc -lr 1
    else
        builtin fc -lr -50
    fi | LC_ALL=C awk '
        function emit_cur() {
            if (has_cur && cur != "" && !seen[cur]++) {
                print cur
            }
        }
        {
            sub(/\r$/, "")
            gsub(/\034/, " ")
        }
        match($0, /^[[:space:]]*[0-9]+\t[ *]/) {
            hdr = substr($0, 1, RLENGTH)
            rest = substr($0, RLENGTH + 1)
            sub(/^[[:space:]]*/, "", hdr)
            sub(/\t.*$/, "", hdr)
            num = hdr + 0
            if (!has_cur || num < prev_num) {
                emit_cur()
                cur = rest
                prev_num = num
                has_cur = 1
                next
            }
        }
        has_cur {
            cur = cur "\034" $0
        }
        END {
            emit_cur()
        }
    '
}

_hs_bash_history_drawer() (
    local init_query="${1:-}"
    [ -r /dev/tty ] && [ -w /dev/tty ] || exit 1
    exec 3>&1

    local tmp_dir="" saved_stty="" prev_h=0 cursor_off=0 cleaned_up=0
    tmp_dir="$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/hs-ctrlr.XXXXXX")" || exit 1
    local tmp_idx="$tmp_dir/idx" tmp_meta="$tmp_dir/meta" tmp_frame="$tmp_dir/frame"
    : > "$tmp_idx"

    saved_stty="$(stty -g </dev/tty)" || { rm -rf "$tmp_dir"; exit 1; }

    _hs_drawer_cleanup() {
        [ "$cleaned_up" -eq 1 ] && return 0
        cleaned_up=1
        if [ "$prev_h" -gt 0 ]; then
            local up_to_top=$((cursor_off - 1))
            local seq=$'\033[?25l\033[?7h\033[0m\r'
            if [ "$up_to_top" -gt 0 ]; then
                seq="${seq}"$'\033['"${up_to_top}A"$'\r'
            fi
            seq="${seq}"$'\033[J\033[1A\r\033[?25h'
            printf '%s' "$seq" >/dev/tty
        else
            printf '\033[?7h\033[?25h' >/dev/tty
        fi
        if [ -n "$saved_stty" ]; then
            stty "$saved_stty" </dev/tty
        fi
        [ -n "$tmp_dir" ] && rm -rf "$tmp_dir"
    }
    trap '_hs_drawer_cleanup' EXIT
    trap 'exit 130' INT TERM HUP
    trap '' TSTP QUIT

    local winch_flag=0
    trap 'winch_flag=1' WINCH

    stty -echo -icanon intr undef quit undef susp undef min 1 time 0 </dev/tty

    local color_mode="16" ascii_mode=0
    [ "${TERM:-}" = "linux" ] && ascii_mode=1
    if [ -n "${NO_COLOR:-}" ]; then
        color_mode="none"
    elif _hs_bash_is_truecolor; then
        color_mode="tc"
    fi

    local r_b02="7;54;66" r_b01="88;110;117" r_b0="131;148;150" r_b1="147;161;161"
    local r_yel="181;137;0" r_blu="38;139;210" r_grn="133;153;0" v
    if [ "$color_mode" = "tc" ]; then
        if [ -n "${_HS_PROMPT_BG_BASE02:-}" ]; then v="${_HS_PROMPT_BG_BASE02#*48;2;}"; r_b02="${v%%m*}"; fi
        if [ -n "${_HS_PROMPT_FG_BASE01:-}" ]; then v="${_HS_PROMPT_FG_BASE01#*38;2;}"; r_b01="${v%%m*}"; fi
        if [ -n "${_HS_PROMPT_FG_BASE0:-}" ];  then v="${_HS_PROMPT_FG_BASE0#*38;2;}";  r_b0="${v%%m*}";  fi
        if [ -n "${_HS_PROMPT_FG_BASE1:-}" ];  then v="${_HS_PROMPT_FG_BASE1#*38;2;}";  r_b1="${v%%m*}";  fi
        if [ -n "${_HS_PROMPT_FG_YELLOW:-}" ]; then v="${_HS_PROMPT_FG_YELLOW#*38;2;}"; r_yel="${v%%m*}"; fi
        if [ -n "${_HS_PROMPT_FG_BLUE:-}" ];   then v="${_HS_PROMPT_FG_BLUE#*38;2;}";   r_blu="${v%%m*}"; fi
        if [ -n "${_HS_PROMPT_FG_GREEN:-}" ];  then v="${_HS_PROMPT_FG_GREEN#*38;2;}";  r_grn="${v%%m*}"; fi
    fi

    local query="$init_query" full_loaded=0 fast_cnt=0
    local sel_idx=0 win_start=0 match_cnt=0 sel_raw=""
    local tty_rows=24 tty_cols=80 item_rows=10

    if [ -n "$query" ]; then
        _hs_bash_hist_build_index full > "$tmp_idx"
        full_loaded=1
    else
        _hs_bash_hist_build_index fast > "$tmp_idx"
        fast_cnt="$(LC_ALL=C wc -l < "$tmp_idx")"
        fast_cnt="${fast_cnt//[[:space:]]/}"
        [ -z "$fast_cnt" ] && fast_cnt=0
    fi

    _hs_drawer_measure_tty() {
        local sz=""
        sz="$(stty size </dev/tty || echo '24 80')"
        tty_rows="${sz%% *}"
        tty_cols="${sz##* }"
        case "$tty_rows" in ''|*[!0-9]*) tty_rows=24 ;; esac
        case "$tty_cols" in ''|*[!0-9]*) tty_cols=80 ;; esac
        [ "$tty_cols" -lt 20 ] && tty_cols=20
        item_rows=$((tty_rows - 4))
        [ "$item_rows" -gt 10 ] && item_rows=10
        [ "$item_rows" -lt 1 ] && item_rows=1
    }

    _hs_drawer_ensure_full() {
        if [ "$full_loaded" -eq 0 ]; then
            _hs_bash_hist_build_index full > "$tmp_idx"
            full_loaded=1
        fi
    }

    _hs_drawer_eval() {
        local do_paint="${1:-1}"
        _hs_drawer_measure_tty
        if [ "$full_loaded" -eq 0 ]; then
            if [ -n "$query" ] || [ $((sel_idx + item_rows + 2)) -ge "${fast_cnt:-0}" ]; then
                _hs_drawer_ensure_full
            fi
        fi
        _HS_Q="$query" LC_ALL=C awk \
            -v sel_req="$sel_idx" \
            -v win_req="$win_start" \
            -v cols="$tty_cols" \
            -v item_rows="$item_rows" \
            -v prev_h="$prev_h" \
            -v cur_off="$cursor_off" \
            -v color_mode="$color_mode" \
            -v ascii_mode="$ascii_mode" \
            -v do_paint="$do_paint" \
            -v meta_out="$tmp_meta" \
            -v frame_out="$tmp_frame" \
            -v c_b02="$r_b02" -v c_b01="$r_b01" -v c_b0="$r_b0" -v c_b1="$r_b1" \
            -v c_yel="$r_yel" -v c_blu="$r_blu" -v c_grn="$r_grn" '
            BEGIN {
                for (b = 0; b < 256; b++) ord[sprintf("%c", b)] = b
                q = ENVIRON["_HS_Q"]
                ntoks = 0
                nraw = split(q, rtoks, /[[:space:]]+/)
                for (k = 1; k <= nraw; k++) {
                    t = rtoks[k]
                    if (t == "") continue
                    neg = 0; a_s = 0; a_e = 0; body = t
                    if (substr(body, 1, 1) == "!") { neg = 1; body = substr(body, 2) }
                    if (substr(body, 1, 1) == "^") { a_s = 1; body = substr(body, 2) }
                    if (length(body) >= 1 && substr(body, length(body), 1) == "$") {
                        a_e = 1
                        body = substr(body, 1, length(body) - 1)
                    }
                    if (body == "") continue
                    ntoks++
                    t_neg[ntoks] = neg
                    t_as[ntoks] = a_s
                    t_ae[ntoks] = a_e
                    t_cs[ntoks] = (body ~ /[A-Z]/) ? 1 : 0
                    t_pat[ntoks] = t_cs[ntoks] ? body : tolower(body)
                    t_len[ntoks] = length(body)
                }
                total_cnt = 0
                match_cnt = 0
            }
            {
                total_cnt++
                raw = $0
                if (ntoks == 0) {
                    match_cnt++
                    m_raw[match_cnt] = raw
                    next
                }
                s_cs = raw
                gsub(/\034/, "\n", s_cs)
                s_lc = tolower(s_cs)
                hlen = length(s_cs)
                ok = 1
                for (k = 1; k <= ntoks; k++) {
                    hay = t_cs[k] ? s_cs : s_lc
                    pat = t_pat[k]
                    plen = t_len[k]
                    if (plen > hlen) {
                        hit = 0
                    } else if (t_as[k] && t_ae[k]) {
                        hit = (hlen == plen && hay == pat) ? 1 : 0
                    } else if (t_as[k]) {
                        hit = (substr(hay, 1, plen) == pat) ? 1 : 0
                    } else if (t_ae[k]) {
                        hit = (substr(hay, hlen - plen + 1, plen) == pat) ? 1 : 0
                    } else {
                        hit = (index(hay, pat) > 0) ? 1 : 0
                    }
                    if (t_neg[k]) {
                        if (hit) { ok = 0; break }
                    } else {
                        if (!hit) { ok = 0; break }
                    }
                }
                if (ok) {
                    match_cnt++
                    m_raw[match_cnt] = raw
                }
            }
            function utf8_cw(str, idx, n, b,    b2, b3, cp) {
                if (b == 9 || b >= 240) return 2
                if (b < 192) return 1
                if (b < 224) {
                    if (idx + 1 <= n) {
                        b2 = ord[substr(str, idx + 1, 1)]
                        if (b == 204 || (b == 205 && b2 <= 175)) return 0
                    }
                    return 1
                }
                if (idx + 2 > n) return 1
                b2 = ord[substr(str, idx + 1, 1)]
                b3 = ord[substr(str, idx + 2, 1)]
                if (b2 < 128 || b2 > 191 || b3 < 128 || b3 > 191) return 1
                cp = (b - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)
                if ((cp >= 8203 && cp <= 8207) || cp == 8288 || (cp >= 8400 && cp <= 8447) || cp == 12441 || cp == 12442 || (cp >= 65024 && cp <= 65039) || (cp >= 65056 && cp <= 65071) || cp == 65279) return 0
                if (cp < 4352) return 1
                if (cp <= 4447 || cp == 8986 || cp == 8987 || cp == 9001 || cp == 9002 || (cp >= 9193 && cp <= 9196) || cp == 9200 || cp == 9203 || cp == 9725 || cp == 9726 || cp == 9748 || cp == 9749 || (cp >= 9776 && cp <= 9783) || (cp >= 9800 && cp <= 9811) || cp == 9855 || (cp >= 9866 && cp <= 9871) || cp == 9875 || cp == 9889 || cp == 9898 || cp == 9899 || cp == 9917 || cp == 9918 || cp == 9924 || cp == 9925 || cp == 9934 || cp == 9940 || cp == 9962 || cp == 9970 || cp == 9971 || cp == 9973 || cp == 9978 || cp == 9981 || cp == 9989 || cp == 9994 || cp == 9995 || cp == 10024 || cp == 10060 || cp == 10062 || (cp >= 10067 && cp <= 10069) || cp == 10071 || (cp >= 10133 && cp <= 10135) || cp == 10160 || cp == 10175 || cp == 11035 || cp == 11036 || cp == 11088 || cp == 11093) return 2
                if (cp >= 11904 && cp <= 42191) return (cp == 12351 || (cp >= 12872 && cp <= 12879)) ? 1 : 2
                if ((cp >= 43360 && cp <= 43388) || (cp >= 44032 && cp <= 55203) || (cp >= 63744 && cp <= 64255) || (cp >= 65040 && cp <= 65049) || (cp >= 65072 && cp <= 65135) || (cp >= 65281 && cp <= 65376) || (cp >= 65504 && cp <= 65510)) return 2
                return 1
            }
            function vis_width(str,    n, idx, b, w) {
                n = length(str); w = 0
                for (idx = 1; idx <= n; idx++) {
                    b = ord[substr(str, idx, 1)]
                    if (b >= 128 && b <= 191) continue
                    w += utf8_cw(str, idx, n, b)
                }
                return w
            }
            function clip_query_tail(str, maxw, ell_s,    n, idx, b, cw, w, start_i) {
                w = vis_width(str)
                q_shown_w = w
                if (w <= maxw) return str
                if (maxw <= 1) { q_shown_w = 1; return ell_s }
                n = length(str); cw = 0; start_i = n + 1
                for (idx = n; idx >= 1; idx--) {
                    b = ord[substr(str, idx, 1)]
                    if (b >= 128 && b <= 191) continue
                    w = utf8_cw(str, idx, n, b)
                    if (cw + w > maxw - 1) break
                    cw += w
                    if (w > 0) start_i = idx
                }
                q_shown_w = 1 + cw
                return ell_s substr(str, start_i)
            }
            function render_item(raw_s, is_sel, avail_w,    hlen, i, k, hay, pat, plen, off, idx, spos, p, tot_w, lim_w, trunc, vis_w, cur_s, out, ch, b, cw, want_s, glyph, s_cs, s_lc) {
                hlen = length(raw_s)
                for (i = 1; i <= hlen; i++) mask[i] = 0
                if (ntoks > 0 && hlen > 0) {
                    s_cs = raw_s
                    gsub(/\034/, "\n", s_cs)
                    s_lc = tolower(s_cs)
                    for (k = 1; k <= ntoks; k++) {
                        if (t_neg[k]) continue
                        hay = t_cs[k] ? s_cs : s_lc
                        pat = t_pat[k]
                        plen = t_len[k]
                        if (plen > hlen) continue
                        if (t_as[k]) {
                            for (p = 1; p <= plen; p++) mask[p] = 1
                        } else if (t_ae[k]) {
                            for (p = hlen - plen + 1; p <= hlen; p++) mask[p] = 1
                        } else {
                            off = 0
                            while ((idx = index(substr(hay, off + 1), pat)) > 0) {
                                spos = off + idx
                                for (p = spos; p < spos + plen; p++) mask[p] = 1
                                off = spos
                            }
                        }
                    }
                }
                tot_w = vis_width(raw_s)
                if (tot_w > avail_w) {
                    lim_w = avail_w - 1
                    trunc = 1
                } else {
                    lim_w = avail_w
                    trunc = 0
                }
                vis_w = 0; cur_s = ""; out = ""
                for (i = 1; i <= hlen; i++) {
                    ch = substr(raw_s, i, 1)
                    b = ord[ch]
                    if (b >= 128 && b <= 191) {
                        out = out ch
                        continue
                    }
                    cw = utf8_cw(raw_s, i, hlen, b)
                    if (vis_w + cw > lim_w || (lim_w == 0 && cw == 0)) break
                    if (b == 28) {
                        want_s = is_sel ? s_sel_dim : s_dim
                        glyph = cont_sym
                    } else {
                        want_s = mask[i] ? (is_sel ? s_sel_hl : s_hl) : (is_sel ? s_sel_fg : s_fg)
                        glyph = (b == 9) ? "  " : ((b < 32 || b == 127) ? "?" : ch)
                    }
                    if (want_s != cur_s) { out = out want_s; cur_s = want_s }
                    out = out glyph
                    vis_w += cw
                }
                if (trunc && avail_w >= 1) {
                    want_s = is_sel ? s_sel_dim : s_dim
                    if (want_s != cur_s) { out = out want_s; cur_s = want_s }
                    out = out ell
                }
                return out
            }
            function rep_str(s, cnt,    r, j) {
                r = ""
                for (j = 0; j < cnt; j++) r = r s
                return r
            }
            END {
                sel = sel_req + 0
                win = win_req + 0
                if (match_cnt == 0) {
                    sel = 0; win = 0; sel_str = ""
                } else {
                    if (sel >= match_cnt) sel = match_cnt - 1
                    if (sel < 0) sel = 0
                    if (sel < win) win = sel
                    if (sel >= win + item_rows) win = sel - item_rows + 1
                    if (win > match_cnt - item_rows) win = match_cnt - item_rows
                    if (win < 0) win = 0
                    sel_str = m_raw[sel + 1]
                }
                printf "%d %d %d\n%s\n", sel, win, match_cnt, sel_str > meta_out
                close(meta_out)
                if (!do_paint) exit 0

                esc = "\033"
                if (ascii_mode + 0 == 1) {
                    tl = "+"; tr = "+"; bl = "+"; br = "+"; hbar = "-"; vbar = "|"
                    ptr = ">"; cont_sym = "\\"; q_sym = "> "; ell = "."
                } else {
                    tl = "\342\225\255"; tr = "\342\225\256"; bl = "\342\225\260"; br = "\342\225\257"
                    hbar = "\342\224\200"; vbar = "\342\224\202"
                    ptr = "\342\226\270"; cont_sym = "\342\206\265"; q_sym = "\342\235\257 "; ell = "\342\200\246"
                }

                if (color_mode == "none") {
                    s_rst = ""; s_bdr = ""; s_dim = ""; s_fg = ""; s_hl = ""
                    s_sel_bg = ""; s_sel_fg = ""; s_sel_hl = ""; s_sel_dim = ""
                    s_ptr = ""; s_prm = ""; s_inf = ""
                } else if (color_mode == "tc") {
                    s_rst = esc "[0m"
                    s_bdr = esc "[38;2;" c_b01 "m"
                    s_dim = s_bdr
                    s_fg = esc "[38;2;" c_b0 "m"
                    s_hl = esc "[38;2;" c_blu "m"
                    s_sel_bg = esc "[48;2;" c_b02 "m"
                    s_sel_fg = esc "[38;2;" c_b1 ";48;2;" c_b02 "m"
                    s_sel_hl = esc "[38;2;" c_blu ";48;2;" c_b02 "m"
                    s_sel_dim = esc "[38;2;" c_b01 ";48;2;" c_b02 "m"
                    s_ptr = esc "[38;2;" c_grn ";48;2;" c_b02 "m"
                    s_prm = esc "[38;2;" c_yel "m"
                    s_inf = esc "[38;2;" c_yel "m"
                } else {
                    s_rst = esc "[0m"
                    s_bdr = esc "[90m"
                    s_dim = s_bdr
                    s_fg = esc "[37m"
                    s_hl = esc "[36m"
                    s_sel_bg = esc "[40m"
                    s_sel_fg = esc "[97;40m"
                    s_sel_hl = esc "[36;40m"
                    s_sel_dim = esc "[90;40m"
                    s_ptr = esc "[32;40m"
                    s_prm = esc "[33m"
                    s_inf = esc "[33m"
                }

                h = item_rows + 3
                buf = esc "[?25l" esc "[?7l"
                if (prev_h + 0 == 0) {
                    buf = buf "\n\r"
                } else {
                    up = (cur_off + 0) - 1
                    if (up > 0) buf = buf esc "[" up "A\r"
                    else buf = buf "\r"
                }

                # Line 1: Top border with title and match count
                cnt_lbl = " " match_cnt "/" total_cnt " "
                title_lbl = " History "
                inner_top = cols - 2
                rem_top = inner_top - length(title_lbl) - length(cnt_lbl)
                if (rem_top < 0) {
                    title_lbl = ""
                    rem_top = inner_top - length(cnt_lbl)
                }
                if (rem_top < 0) {
                    cnt_lbl = ""
                    rem_top = inner_top
                }
                buf = buf s_bdr tl title_lbl rep_str(hbar, rem_top) s_inf cnt_lbl s_bdr tr s_rst "\n\r"

                # Line 2: Search query bar
                q_clean = q
                gsub(/[[:cntrl:]]/, " ", q_clean)
                q_avail = cols - 6
                if (q_avail < 1) q_avail = 1
                q_disp = clip_query_tail(q_clean, q_avail, ell)
                q_cur_col = 5 + q_shown_w
                if (q_cur_col > cols - 1) q_cur_col = cols - 1
                buf = buf s_bdr vbar s_rst " " s_prm q_sym s_fg q_disp s_rst esc "[K" esc "[" cols "G" s_bdr vbar s_rst "\n\r"

                # Lines 3 .. 2 + item_rows: History rows
                avail_item = cols - 6
                if (avail_item < 1) avail_item = 1
                for (r = 0; r < item_rows; r++) {
                    idx0 = win + r
                    if (match_cnt == 0 && r == 0) {
                        msg = (total_cnt == 0) ? "(history is empty)" : "(no matching history entries)"
                        if (length(msg) > avail_item) msg = substr(msg, 1, avail_item)
                        buf = buf s_bdr vbar s_rst "   " s_dim msg s_rst esc "[K" esc "[" cols "G" s_bdr vbar s_rst "\n\r"
                    } else if (idx0 < match_cnt) {
                        is_s = (idx0 == sel) ? 1 : 0
                        row_txt = render_item(m_raw[idx0 + 1], is_s, avail_item)
                        if (is_s) {
                            buf = buf s_bdr vbar s_sel_bg " " s_ptr ptr " " row_txt s_sel_bg esc "[K" esc "[" cols "G" s_rst s_bdr vbar s_rst "\n\r"
                        } else {
                            buf = buf s_bdr vbar s_rst "   " row_txt s_rst esc "[K" esc "[" cols "G" s_bdr vbar s_rst "\n\r"
                        }
                    } else {
                        buf = buf s_bdr vbar s_rst esc "[K" esc "[" cols "G" s_bdr vbar s_rst "\n\r"
                    }
                }

                # Line h: Clear from col 1 to end of screen (wiping leftover rows after shrink without scrolling), then draw bottom command-bar border
                sep_bot = (ascii_mode + 0 == 1) ? " | " : " \302\267 "
                ftr_lbl = " Enter/Tab: place" sep_bot "Esc: cancel "
                inner_bot = cols - 2
                if (vis_width(ftr_lbl) > inner_bot - 2) {
                    ftr_lbl = " Enter/Tab" sep_bot "Esc "
                }
                if (vis_width(ftr_lbl) > inner_bot - 2) {
                    ftr_lbl = ""
                }
                fw_bot = vis_width(ftr_lbl)
                lead_bot = (fw_bot > 0) ? ((inner_bot - fw_bot >= 3) ? 3 : 1) : 0
                rem_bot = inner_bot - lead_bot - fw_bot
                buf = buf esc "[J" s_bdr bl rep_str(hbar, lead_bot) ftr_lbl rep_str(hbar, rem_bot) br s_rst

                # Park visible cursor right after query on Line 2 (h - 2 lines above Line h)
                up_q = h - 2
                if (up_q > 0) buf = buf esc "[" up_q "A"
                buf = buf esc "[" q_cur_col "G" esc "[?7h" esc "[?25h"

                printf "%s", buf > frame_out
                close(frame_out)
            }
        ' "$tmp_idx"

        local meta_hdr=""
        {
            IFS= read -r meta_hdr || true
            IFS= read -r sel_raw || true
        } < "$tmp_meta"
        if [ -n "$meta_hdr" ]; then
            sel_idx="${meta_hdr%% *}"
            local rest_m="${meta_hdr#* }"
            win_start="${rest_m%% *}"
            match_cnt="${rest_m##* }"
        fi

        if [ "$do_paint" -eq 1 ]; then
            local frame_data=""
            IFS= read -r -d '' frame_data < "$tmp_frame" || true
            printf '%s' "$frame_data" >/dev/tty
            prev_h=$((item_rows + 3))
            cursor_off=2
        fi
    }

    _hs_drawer_read_byte() {
        local allow_winch="${1:-0}"
        REPLY=""
        if [ "${_HS_BASH_FORCE_LEGACY_CTRL_R:-0}" != "1" ] && (( BASH_VERSINFO[0] >= 4 )); then
            local k="" rc=0 cur_sz=""
            while true; do
                k=""
                rc=0
                LC_ALL=C IFS= read -r -d '' -n 1 -t 0.25 k </dev/tty || rc=$?
                if [ "$rc" -eq 0 ]; then
                    REPLY="$k"
                    return 0
                fi
                if [ "$allow_winch" -eq 1 ]; then
                    if [ "$winch_flag" -eq 1 ]; then
                        return 2
                    fi
                    if [ "$rc" -gt 128 ]; then
                        cur_sz="$(stty size </dev/tty || printf '%s %s' "$tty_rows" "$tty_cols")"
                        if [ "$cur_sz" != "$tty_rows $tty_cols" ]; then
                            winch_flag=1
                            return 2
                        fi
                    fi
                fi
                if [ "$rc" -gt 128 ]; then
                    continue
                fi
                return 1
            done
        else
            local raw=""
            raw="$(dd bs=1 count=1 </dev/tty 2>/dev/null; printf x)" || {
                [ "$allow_winch" -eq 1 ] && [ "$winch_flag" -eq 1 ] && return 2
                return 1
            }
            raw="${raw%x}"
            if [ -z "$raw" ]; then
                [ "$allow_winch" -eq 1 ] && [ "$winch_flag" -eq 1 ] && return 2
                return 1
            fi
            REPLY="$raw"
            return 0
        fi
    }

    _hs_drawer_read_esc_byte() {
        REPLY=""
        if [ "${_HS_BASH_FORCE_LEGACY_CTRL_R:-0}" != "1" ] && (( BASH_VERSINFO[0] >= 4 )); then
            local k=""
            if LC_ALL=C IFS= read -r -d '' -n 1 -t 0.05 k </dev/tty; then
                REPLY="$k"
                return 0
            fi
            return 1
        else
            local raw=""
            stty min 0 time 1 </dev/tty
            raw="$(dd bs=1 count=1 </dev/tty 2>/dev/null; printf x)" || true
            stty min 1 time 0 </dev/tty
            raw="${raw%x}"
            [ -n "$raw" ] || return 1
            REPLY="$raw"
            return 0
        fi
    }

    local dirty=0 has_pushed=0 pushed_byte=""
    _hs_drawer_eval 1

    while true; do
        if [ "$winch_flag" -eq 1 ]; then
            winch_flag=0
            _hs_drawer_eval 1
        fi
        local ch=""
        if [ "$has_pushed" -eq 1 ]; then
            ch="$pushed_byte"
            has_pushed=0
            pushed_byte=""
        else
            if [ "$dirty" -eq 1 ]; then
                _hs_drawer_eval 1
                dirty=0
            fi
            local rb_rc=0
            _hs_drawer_read_byte 1 || rb_rc=$?
            if [ "$rb_rc" -eq 2 ] || { [ "$rb_rc" -ne 0 ] && [ "$winch_flag" -eq 1 ]; }; then
                continue
            elif [ "$rb_rc" -ne 0 ]; then
                exit 130
            fi
            ch="$REPLY"
        fi

        local ord=0
        if [ -n "$ch" ]; then
            LC_ALL=C printf -v ord '%d' "'$ch"
        fi

        case "$ord" in
            3|7)
                # Ctrl+c or Ctrl+g: cancel cleanly without mutating READLINE_LINE
                exit 130
                ;;
            4)
                # Ctrl+d: cancel when query is empty
                [ -z "$query" ] && exit 130
                ;;
            9|10|13)
                # Tab, LF, or CR: flush any dirty query, then place selection without auto-executing
                if [ "$dirty" -eq 1 ]; then
                    sel_idx=0
                    win_start=0
                    _hs_drawer_eval 0
                    dirty=0
                fi
                if [ "$match_cnt" -gt 0 ] && [ -n "$sel_raw" ]; then
                    local final_cmd="${sel_raw//$'\034'/$'\n'}"
                    printf '%s' "$final_cmd" >&3
                    exit 0
                elif [ -n "$query" ]; then
                    printf '%s' "$query" >&3
                    exit 0
                fi
                exit 130
                ;;
            14|18)
                # Ctrl+n or Ctrl+r: next older match (down)
                if [ "$dirty" -eq 1 ]; then
                    sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                fi
                sel_idx=$((sel_idx + 1))
                _hs_drawer_eval 1
                ;;
            16|19)
                # Ctrl+p or Ctrl+s: previous newer match (up)
                if [ "$dirty" -eq 1 ]; then
                    sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                fi
                [ "$sel_idx" -gt 0 ] && sel_idx=$((sel_idx - 1))
                _hs_drawer_eval 1
                ;;
            21)
                # Ctrl+u: clear query
                if [ -n "$query" ]; then
                    query=""
                    sel_idx=0
                    win_start=0
                    dirty=1
                fi
                ;;
            23)
                # Ctrl+w: delete previous word
                if [ -n "$query" ]; then
                    local trimmed="${query%"${query##*[![:space:]]}"}"
                    local last_word="${trimmed##*[[:space:]]}"
                    query="${trimmed%"$last_word"}"
                    sel_idx=0
                    win_start=0
                    dirty=1
                fi
                ;;
            8|127)
                # Backspace
                if [ -n "$query" ]; then
                    _hs_bash_utf8_pop_char "$query"
                    query="$REPLY"
                    sel_idx=0
                    win_start=0
                    dirty=1
                fi
                ;;
            27)
                # ESC or CSI/SS3/bracketed-paste sequence
                if ! _hs_drawer_read_esc_byte; then
                    exit 130
                fi
                local e1="$REPLY"
                if [ "$e1" = "[" ] || [ "$e1" = "O" ]; then
                    if ! _hs_drawer_read_esc_byte; then
                        exit 130
                    fi
                    local seq="$REPLY"
                    if [ "$e1" = "[" ]; then
                        case "$seq" in
                            [0-9])
                                while _hs_drawer_read_esc_byte; do
                                    seq="${seq}${REPLY}"
                                    case "$REPLY" in
                                        [~A-Za-z]) break ;;
                                    esac
                                done
                                ;;
                        esac
                    fi
                    case "${e1}${seq}" in
                        "[A"|"OA")
                            if [ "$dirty" -eq 1 ]; then
                                sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                            fi
                            [ "$sel_idx" -gt 0 ] && sel_idx=$((sel_idx - 1))
                            _hs_drawer_eval 1
                            ;;
                        "[B"|"OB")
                            if [ "$dirty" -eq 1 ]; then
                                sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                            fi
                            sel_idx=$((sel_idx + 1))
                            _hs_drawer_eval 1
                            ;;
                        "[5~")
                            if [ "$dirty" -eq 1 ]; then
                                sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                            fi
                            sel_idx=$((sel_idx - item_rows))
                            [ "$sel_idx" -lt 0 ] && sel_idx=0
                            _hs_drawer_eval 1
                            ;;
                        "[6~")
                            if [ "$dirty" -eq 1 ]; then
                                sel_idx=0; win_start=0; _hs_drawer_eval 0; dirty=0
                            fi
                            sel_idx=$((sel_idx + item_rows))
                            _hs_drawer_eval 1
                            ;;
                        "[200~")
                            # Bracketed paste: accumulate until \e[201~ without treating embedded newlines as Enter
                            local paste_buf=""
                            while _hs_drawer_read_byte; do
                                [ "$REPLY" = $'\003' ] && exit 130
                                paste_buf="${paste_buf}${REPLY}"
                                if [[ "$paste_buf" == *$'\033[201~' ]]; then
                                    paste_buf="${paste_buf%$'\033[201~'}"
                                    break
                                fi
                            done
                            paste_buf="${paste_buf//$'\r'/ }"
                            paste_buf="${paste_buf//$'\n'/ }"
                            paste_buf="${paste_buf//$'\t'/ }"
                            if [ -n "$paste_buf" ]; then
                                query="${query}${paste_buf}"
                                sel_idx=0
                                win_start=0
                                dirty=1
                            fi
                            ;;
                    esac
                fi
                ;;
            *)
                if [ "$ord" -ge 32 ]; then
                    query="${query}${ch}"
                    sel_idx=0
                    win_start=0
                    dirty=1
                    if [ "${_HS_BASH_FORCE_LEGACY_CTRL_R:-0}" != "1" ] && (( BASH_VERSINFO[0] >= 4 )); then
                        local nk="" nord=0
                        while LC_ALL=C IFS= read -r -d '' -n 1 -t 0.002 nk </dev/tty; do
                            nord=0
                            [ -n "$nk" ] && LC_ALL=C printf -v nord '%d' "'$nk"
                            if [ "$nord" -ge 32 ] && [ "$nord" -ne 127 ]; then
                                query="${query}${nk}"
                            else
                                has_pushed=1
                                pushed_byte="$nk"
                                break
                            fi
                        done
                    fi
                fi
                ;;
        esac
    done
)

_hs_bash_history_widget() {
    local picked=""
    if [ "${_HS_BASH_FORCE_LEGACY_CTRL_R:-0}" != "1" ] && (( BASH_VERSINFO[0] >= 4 )); then
        if picked="$(_hs_bash_history_drawer "${READLINE_LINE:-}")"; then
            READLINE_LINE="$picked"
            READLINE_POINT=2147483647
        fi
    else
        if picked="$(_hs_bash_history_drawer "")" && [ -n "$picked" ]; then
            local HISTCONTROL="" HISTIGNORE="" HISTTIMEFORMAT="" _hs_hnum=""
            builtin history -s -- "$picked"
            _hs_hnum="$(builtin history 1)"
            _hs_hnum="${_hs_hnum#"${_hs_hnum%%[! ]*}"}"
            _hs_hnum="${_hs_hnum%%[!0-9]*}"
            if [ -n "$_hs_hnum" ]; then
                builtin bind -m emacs-standard "\"\C-x\C-r2\": \"\e${_hs_hnum}\C-x\C-r0\C-e\""
                builtin bind -m vi-command "\"\C-x\C-r2\": \"${_hs_hnum}\C-x\C-r0A\""
                builtin bind -m vi-insert "\"\C-x\C-r2\": \"\e${_hs_hnum}\C-x\C-r0A\""
                return 0
            fi
        fi
        builtin bind -m emacs-standard '"\C-x\C-r2": "\C-x\C-r9"'
        builtin bind -m vi-command '"\C-x\C-r2": "\C-x\C-r9"'
        builtin bind -m vi-insert '"\C-x\C-r2": "\C-x\C-r9"'
    fi
}
