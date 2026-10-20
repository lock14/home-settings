#!/bin/bash
# Shared test assertion library for home-settings test suites.

TESTS_PASSED=0
TESTS_FAILED=0

COLOR_PASS="\033[32m"
COLOR_FAIL="\033[31m"
COLOR_RESET="\033[0m"

# Isolate all test suites from any live caller tmux session by default
unset TMUX TMUX_PANE

# Preserve mise data/cache/state paths when individual tests override HOME or XDG_*
export MISE_DATA_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"

# Ethan Schoonover Solarized Dark TrueColor ANSI 24-bit Escape Sequences
case "${COLORTERM:-}" in
    truecolor|24bit) ;;
    *) export COLORTERM="truecolor" ;;
esac
SOL_BASE03=$'\033[38;2;0;43;54m'       # #002B36
SOL_BASE02=$'\033[38;2;7;54;66m'       # #073642
SOL_BASE01=$'\033[38;2;88;110;117m'    # #586E75
SOL_BASE00=$'\033[38;2;101;123;131m'   # #657B83
SOL_BASE0=$'\033[38;2;131;148;150m'    # #839496
SOL_BASE1=$'\033[38;2;147;161;161m'    # #93A1A1
SOL_BASE2=$'\033[38;2;238;232;213m'    # #EEE8D5
SOL_BASE3=$'\033[38;2;253;246;227m'    # #FDF6E3

SOL_YELLOW=$'\033[38;2;181;137;0m'     # #B58900
SOL_ORANGE=$'\033[38;2;203;75;22m'     # #CB4B16
SOL_RED=$'\033[38;2;220;50;47m'        # #DC322F
SOL_MAGENTA=$'\033[38;2;211;54;130m'   # #D33682
SOL_VIOLET=$'\033[38;2;108;113;196m'   # #6C71C4
SOL_BLUE=$'\033[38;2;38;139;210m'      # #268BD2
SOL_CYAN=$'\033[38;2;42;161;152m'      # #2AA198
SOL_GREEN=$'\033[38;2;133;153;0m'      # #859900
SOL_RESET=$'\033[0m'

export SOL_BASE03 SOL_BASE02 SOL_BASE01 SOL_BASE00 SOL_BASE0 SOL_BASE1 SOL_BASE2 SOL_BASE3
export SOL_YELLOW SOL_ORANGE SOL_RED SOL_MAGENTA SOL_VIOLET SOL_BLUE SOL_CYAN SOL_GREEN SOL_RESET

pass() {
    printf '  %b✔ PASS:%b %s\n' "$COLOR_PASS" "$COLOR_RESET" "$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    printf '  %b✘ FAIL:%b %s\n' "$COLOR_FAIL" "$COLOR_RESET" "$1"
    if [ $# -ge 2 ] && [ -n "$2" ]; then
        printf '    %s\n' "$2"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local desc="$3"

    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc" "Expected '$expected', got '$actual'"
    fi
}

assert_match() {
    local pattern="$1"
    local string="$2"
    local desc="$3"

    if [[ "$string" == *"$pattern"* ]]; then
        pass "$desc"
    else
        fail "$desc" "Expected string to contain '$pattern', got: $string"
    fi
}

assert_file() {
    local path="$1"
    local desc="${2:-File exists: $path}"

    if [ -f "$path" ]; then
        pass "$desc"
    else
        fail "$desc" "Expected file to exist at: $path"
    fi
}

assert_symlink() {
    local path="$1"
    local target="${2:-}"
    local desc="${3:-Symlink exists: $path}"

    if [ -L "$path" ]; then
        if [ -n "$target" ]; then
            local actual_target
            actual_target="$(readlink "$path")"
            if [[ "$actual_target" == *"$target"* ]]; then
                pass "$desc"
            else
                fail "$desc" "Symlink points to '$actual_target', expected '$target'"
            fi
        else
            pass "$desc"
        fi
    else
        fail "$desc" "Expected symlink at: $path"
    fi
}

wait_for_nvim_socket() {
    local sock="$1"
    local max_tries="${2:-30}"
    local check_rpc="${3:-0}"
    local tries=0
    while [ "$tries" -lt "$max_tries" ]; do
        if [ -S "$sock" ]; then
            if [ "$check_rpc" != "1" ] || nvim --headless --server "$sock" --remote-expr "1" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 0.05
        tries=$((tries + 1))
    done
    return 1
}

# Run headless Neovim safely with stdin closed (</dev/null), a separate
# trailing -c "qall!" (so Ex/Lua errors in earlier -c commands never leave
# Neovim hanging in its event loop), and a bounded timeout.
run_nvim_headless() {
    local timeout_sec="${NVIM_HEADLESS_TIMEOUT:-30}"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" nvim --headless "$@" -c "qall!" </dev/null
    else
        nvim --headless "$@" -c "qall!" </dev/null
    fi
}

parse_subshell_results() {
    local pass_prefix="${1:-}"
    local fail_prefix="${2:-}"
    local line rest
    while IFS= read -r line; do
        if [[ "$line" == PASS:* ]]; then
            pass "${pass_prefix}${line#PASS:}"
        elif [[ "$line" == FAIL:* ]]; then
            rest="${line#FAIL:}"
            fail "${fail_prefix}${rest%%:*}" "${rest#*:}"
        fi
    done
}

lint_documentation() {
    local root_dir="${1:-.}"
    python3 - "$root_dir" <<'PY'
import json
import os
import re
import sys
import unicodedata

root_dir = sys.argv[1]

doc_personal_path_re = re.compile(
    r"(?i)(/home/[a-z0-9_-]+|/Users/[a-z0-9_-]+|C:\\Users\\[a-z0-9_-]+)"
)
decorative_emoji_re = re.compile(
    r"([\U0001F300-\U0001FAFF\u26A1\u2705\u2728\u274C\U0001F6AB]|:(?:white_check_mark|x):)"
)
italic_aside_re = re.compile(r"(?i)(\*|_)\((?:note|tip|alternatively)\b")
bold_table_cell_re = re.compile(r"^\|\s*\*\*[^*]+\*\*\s*\|")
html_comment_re = re.compile(r"<!--.*?-->")
ascii_arrow_re = re.compile(
    r"(<->|->|<-|=>|\$\\to\$|\$\\rightarrow\$|\$\\leftrightarrow\$|\$\$)"
)
heading_link_re = re.compile(r"\[([^\]]+)\]\([^)]+\)")
url_re = re.compile(r"https?://\S+")
markdown_link_target_re = re.compile(r"\]\((?:\\.|[^)])*\)")
prose_slash_re = re.compile(r"(?<![/\w.-])([A-Za-z]{2,}/[A-Za-z]{2,})(?![/\w.-])")
allowed_slash_terms = {"i/o", "ci/cd", "tcp/ip", "ssl/tls", "n/a"}
prose_amp_re = re.compile(r"\s&\s")
accidental_underscore_italic_re = re.compile(
    r"\b[A-Za-z0-9]+_[^_\n`]*[\s,;:/][^_\n`]*_[A-Za-z0-9]+\b"
)
italic_wrapped_re = re.compile(
    r"(?<![*_\\])(\*|_)(\s*`[^`]+`\s*|\s*\[[^\]]+\]\([^)]+\)\s*)\1(?![*_])"
)
link_italic_re = re.compile(r"\[\s*(\*|_)[^\]*_]+\1\s*\]\([^)]+\)")


def github_heading_slug(heading):
    stripped = heading_link_re.sub(r"\1", heading)
    s = stripped.strip().lower()
    out = []
    for ch in s:
        cat = unicodedata.category(ch)
        if cat.startswith("L") or cat.startswith("N") or ch in ("-", "_"):
            out.append(ch)
        elif ch == " ":
            out.append("-")
    return "".join(out)


def collect_markdown_heading_slugs(text):
    slugs = set()
    slug_counts = {}
    in_fence = False
    for line in text.split("\n"):
        trimmed = line.strip()
        if trimmed.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if trimmed.startswith("#"):
            title = trimmed.lstrip("#").strip()
            if title:
                base_slug = github_heading_slug(title)
                if base_slug:
                    count = slug_counts.get(base_slug, 0)
                    slug_counts[base_slug] = count + 1
                    slug = base_slug if count == 0 else f"{base_slug}-{count}"
                    slugs.add(slug)
    return slugs


def find_closing_backticks(s, tick_count):
    i = 0
    n = len(s)
    while i <= n - tick_count:
        if s[i] != "`":
            i += 1
            continue
        run = 0
        while i + run < n and s[i + run] == "`":
            run += 1
        if run == tick_count:
            return i
        i += run
    return -1


def strip_inline_code_and_check(line):
    out = []
    i = 0
    n = len(line)
    unmatched = False
    while i < n:
        if line[i] == "`":
            tick_count = 0
            while i + tick_count < n and line[i + tick_count] == "`":
                tick_count += 1
            close_rel = find_closing_backticks(line[i + tick_count :], tick_count)
            if close_rel >= 0:
                i += tick_count + close_rel + tick_count
                continue
            unmatched = True
            out.append(line[i : i + tick_count])
            i += tick_count
            continue
        out.append(line[i])
        i += 1
    return "".join(out), unmatched


def strip_inline_code(line):
    cleaned, _ = strip_inline_code_and_check(line)
    return cleaned


def find_stacked_formatting(line):
    m = italic_wrapped_re.search(line)
    if m:
        return m.group(0)
    m = link_italic_re.search(line)
    if m:
        return m.group(0)

    i = 0
    n = len(line)
    while i < n:
        if line[i] == "`":
            tick_count = 0
            while i + tick_count < n and line[i + tick_count] == "`":
                tick_count += 1
            close_rel = find_closing_backticks(line[i + tick_count :], tick_count)
            if close_rel >= 0:
                i += tick_count + close_rel + tick_count
                continue
            i += tick_count
            continue

        if line.startswith("***", i):
            end = line.find("***", i + 3)
            if end >= 0:
                return line[i : end + 3]

        if line.startswith("_**", i):
            end = line.find("**_", i + 3)
            if end >= 0:
                return line[i : end + 3]

        if line.startswith("**", i):
            end = line.find("**", i + 2)
            if end >= 0:
                inner = line[i + 2 : end]
                full = line[i : end + 2]
                if "`" in inner:
                    return full
                if "[" in inner and "](" in inner:
                    return full
                if (
                    inner.startswith("_")
                    and inner.endswith("_")
                    and len(inner) > 2
                ) or (
                    inner.startswith("*")
                    and inner.endswith("*")
                    and len(inner) > 2
                ):
                    return full
                i = end + 2
                continue

        if line[i] == "[":
            close_bracket = line.find("]", i + 1)
            if close_bracket >= 0:
                after_bracket = close_bracket + 1
                if after_bracket < n and line[after_bracket] == "(":
                    link_text = line[i + 1 : close_bracket]
                    if "**" in link_text:
                        close_paren = line.find(")", after_bracket + 1)
                        if close_paren >= 0:
                            return line[i : close_paren + 1]

        i += 1
    return ""


def extract_markdown_link_targets(line):
    cleaned = strip_inline_code(line)
    targets = []
    pos = 0
    n = len(cleaned)
    while pos < n:
        idx = cleaned.find("](", pos)
        if idx < 0:
            break
        start = idx + 2
        depth = 1
        raw = []
        j = start
        while j < n and depth > 0:
            if cleaned[j] == "\\" and j + 1 < n:
                raw.append(cleaned[j + 1])
                j += 2
                continue
            if cleaned[j] == "(":
                depth += 1
                raw.append("(")
                j += 1
                continue
            if cleaned[j] == ")":
                depth -= 1
                if depth == 0:
                    break
                raw.append(")")
                j += 1
                continue
            raw.append(cleaned[j])
            j += 1
        if depth != 0:
            break
        target = "".join(raw).strip()
        fields = target.split()
        if fields:
            target = fields[0]
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        if target:
            targets.append(target)
        pos = j + 1
    return targets


doc_files = [
    "README.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "SECURITY.md",
    os.path.join(".github", "PULL_REQUEST_TEMPLATE.md"),
]
yaml_files = [
    os.path.join(".github", "ISSUE_TEMPLATE", "bug_report.yml"),
    os.path.join(".github", "ISSUE_TEMPLATE", "feature_request.yml"),
    os.path.join(".github", "ISSUE_TEMPLATE", "config.yml"),
    os.path.join(".github", "workflows", "benchmark.yml"),
    os.path.join(".github", "workflows", "ci.yml"),
    os.path.join(".github", "workflows", "security.yml"),
]

errors = []
heading_slug_cache = {}

for rel_yaml in yaml_files:
    yaml_path = os.path.join(root_dir, rel_yaml)
    if not os.path.isfile(yaml_path):
        continue
    where = yaml_path.replace("\\", "/")
    with open(yaml_path, encoding="utf-8") as fh:
        text = fh.read()
    m = doc_personal_path_re.search(text)
    if m:
        errors.append(f'{where}: contains personal path "{m.group(0)}"')
    m = decorative_emoji_re.search(text)
    if m:
        errors.append(
            f'{where}: contains decorative emoji or shortcode "{m.group(0)}"'
        )

for rel_doc in doc_files:
    doc_path = os.path.join(root_dir, rel_doc)
    if not os.path.isfile(doc_path):
        continue
    where = doc_path.replace("\\", "/")
    with open(doc_path, encoding="utf-8") as fh:
        text = fh.read()

    m = doc_personal_path_re.search(text)
    if m:
        errors.append(f'{where}: contains personal path "{m.group(0)}"')
    m = decorative_emoji_re.search(text)
    if m:
        errors.append(
            f'{where}: contains decorative emoji or shortcode "{m.group(0)}"'
        )

    lines = text.split("\n")
    in_fence = False
    fence_lang = ""
    fence_start_line = 0
    fence_buf = []
    heading_slugs = collect_markdown_heading_slugs(text)
    heading_slug_cache[os.path.abspath(doc_path)] = heading_slugs

    for idx, line in enumerate(lines):
        line_num = idx + 1
        trimmed = line.strip()
        if trimmed.startswith("```"):
            if not in_fence:
                in_fence = True
                fence_lang = trimmed[3:].strip().lower()
                fence_start_line = line_num
                fence_buf = []
            else:
                if fence_lang == "json" and rel_doc in (
                    "README.md",
                    "CONTRIBUTING.md",
                    "AGENTS.md",
                ):
                    try:
                        json.loads("\n".join(fence_buf))
                    except Exception:
                        errors.append(
                            f"{where}: invalid JSON code block starting at line {fence_start_line}"
                        )
                in_fence = False
                fence_lang = ""
            continue
        if in_fence:
            fence_buf.append(line)
            continue

        if trimmed == "---":
            errors.append(
                f"{where}: contains horizontal rule divider '---' at line {line_num}"
            )

        if rel_doc in ("README.md", "CONTRIBUTING.md", "AGENTS.md"):
            m = bold_table_cell_re.search(trimmed)
            if m:
                errors.append(
                    f'{where}: contains bolded first-column table cell "{m.group(0).strip()}" at line {line_num}'
                )

        stacked = find_stacked_formatting(line)
        if stacked:
            errors.append(f'{where}: contains stacked formatting span "{stacked}"')

        stripped_code, has_unmatched_tick = strip_inline_code_and_check(line)
        if has_unmatched_tick:
            errors.append(
                f"{where}: contains unmatched inline backtick at line {line_num}"
            )

        cleaned_line = html_comment_re.sub("", stripped_code)
        m = italic_aside_re.search(cleaned_line)
        if m:
            errors.append(
                f'{where}: contains italic parenthetical aside "{m.group(0)}"'
            )
        m = ascii_arrow_re.search(cleaned_line)
        if m:
            errors.append(
                f'{where}: contains ASCII arrow "{m.group(0)}" at line {line_num}'
            )

        if rel_doc in ("README.md", "CONTRIBUTING.md", "AGENTS.md"):
            prose_line = url_re.sub(
                "", markdown_link_target_re.sub("]()", cleaned_line)
            )
            m = accidental_underscore_italic_re.search(prose_line)
            if m:
                errors.append(
                    f'{where}: contains unbackticked underscore span "{m.group(0)}" at line {line_num}'
                )
            for sm in prose_slash_re.finditer(prose_line):
                token = sm.group(1)
                if token.lower() not in allowed_slash_terms:
                    errors.append(
                        f'{where}: contains prose slash "{token}" at line {line_num}'
                    )
            if prose_amp_re.search(prose_line):
                errors.append(
                    f'{where}: contains prose ampersand " & " at line {line_num}'
                )

    if rel_doc in ("README.md", "CONTRIBUTING.md", "AGENTS.md"):
        in_fence = False
        doc_dir = os.path.dirname(doc_path)
        for line in lines:
            trimmed = line.strip()
            if trimmed.startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in extract_markdown_link_targets(line):
                if target.startswith("#"):
                    slug = target[1:]
                    if slug not in heading_slugs:
                        errors.append(f'{where}: broken anchor link "{target}"')
                    continue
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                parts = target.split("#", 1)
                rel_target = parts[0]
                frag = parts[1] if len(parts) > 1 else ""
                if not rel_target:
                    continue
                target_path = os.path.join(
                    doc_dir, rel_target.replace("/", os.sep)
                )
                if not os.path.exists(target_path):
                    errors.append(
                        f'{where}: broken relative file link "{target}"'
                    )
                    continue
                if frag and target_path.lower().endswith(".md") and os.path.isfile(target_path):
                    abs_target = os.path.abspath(target_path)
                    if abs_target not in heading_slug_cache:
                        with open(abs_target, encoding="utf-8") as tfh:
                            heading_slug_cache[abs_target] = (
                                collect_markdown_heading_slugs(tfh.read())
                            )
                    if frag not in heading_slug_cache[abs_target]:
                        errors.append(
                            f'{where}: broken anchor link "{target}"'
                        )

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    sys.exit(1)
PY
}

test_summary() {
    printf '\n========================================\n'
    printf 'Summary: %s passed, %s failed\n' "$TESTS_PASSED" "$TESTS_FAILED"
    printf '========================================\n'

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}
