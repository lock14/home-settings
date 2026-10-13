; Base highlights for markdown_inline (supersedes upstream to eliminate rogue OSC 8 url metadata)

(code_span) @markup.raw @nospell

(emphasis) @markup.italic

(strong_emphasis) @markup.strong

(strikethrough) @markup.strikethrough

(shortcut_link
  (link_text) @nospell)

; Conceal backslash in backslash escapes
((backslash_escape) @conceal
  (#offset! @conceal 0 0 0 -1)
  (#set! conceal ""))

; Conceal backslash in hard line breaks
((hard_line_break
  "\\" @conceal)
  (#set! conceal ""))

[
  (backslash_escape)
  (hard_line_break)
] @string.escape

; Conceal codeblock and text style markers
([
  (code_span_delimiter)
  (emphasis_delimiter)
] @conceal
  (#set! conceal ""))

; Conceal inline links
(inline_link
  [
    "["
    "]"
    "("
    (link_destination)
    ")"
  ] @markup.link
  (#set! conceal ""))

[
  (link_label)
  (link_text)
  (link_title)
  (image_description)
] @markup.link.label

; Conceal image links
(image
  [
    "!"
    "["
    "]"
    "("
    (link_destination)
    ")"
  ] @markup.link
  (#set! conceal ""))

; Conceal full reference links
(full_reference_link
  [
    "["
    "]"
    (link_label)
  ] @markup.link
  (#set! conceal ""))

; Conceal collapsed reference links
(collapsed_reference_link
  [
    "["
    "]"
  ] @markup.link
  (#set! conceal ""))

; Conceal shortcut links
(shortcut_link
  [
    "["
    "]"
  ] @markup.link
  (#set! conceal ""))

[
  (link_destination)
  (uri_autolink)
  (email_autolink)
] @markup.link.url @nospell

(entity_reference) @nospell

; Replace common HTML entities.
((entity_reference) @character.special
  (#eq? @character.special "&nbsp;")
  (#set! conceal " "))

((entity_reference) @character.special
  (#eq? @character.special "&lt;")
  (#set! conceal "<"))

((entity_reference) @character.special
  (#eq? @character.special "&gt;")
  (#set! conceal ">"))

((entity_reference) @character.special
  (#eq? @character.special "&amp;")
  (#set! conceal "&"))

((entity_reference) @character.special
  (#eq? @character.special "&quot;")
  (#set! conceal "\""))

((entity_reference) @character.special
  (#any-of? @character.special "&ensp;" "&emsp;")
  (#set! conceal " "))

; Delimiters: Backticks in code spans -> Solarized Base01
(code_span_delimiter) @markup.raw.delimiter

; Delimiters: Bold double asterisks / underscores -> Solarized Base1 (Bold)
(strong_emphasis
  (emphasis_delimiter) @markup.strong)

; Delimiters: Italic single asterisk / underscore -> Solarized Base0 (Italic)
(emphasis
  (emphasis_delimiter) @markup.italic)

; Links: Punctuation brackets [], () -> Solarized Base01
(inline_link
  [ "[" "]" "(" ")" ] @markup.link)

(inline_link
  (link_text) @markup.link.label)

(inline_link
  (link_destination) @markup.link.url)

; Autolinks: <https://...> and <user@example.com> -> Solarized Cyan
[
  (uri_autolink)
  (email_autolink)
] @markup.link.url

; GitHub Alert Callouts ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION])
((shortcut_link
  "[" @markup.alert.note
  (link_text) @markup.alert.note
  "]" @markup.alert.note) @_link
  (#eq? @_link "[!NOTE]")
  (#set! priority 120))

((shortcut_link
  "[" @markup.alert.tip
  (link_text) @markup.alert.tip
  "]" @markup.alert.tip) @_link
  (#eq? @_link "[!TIP]")
  (#set! priority 120))

((shortcut_link
  "[" @markup.alert.important
  (link_text) @markup.alert.important
  "]" @markup.alert.important) @_link
  (#eq? @_link "[!IMPORTANT]")
  (#set! priority 120))

((shortcut_link
  "[" @markup.alert.warning
  (link_text) @markup.alert.warning
  "]" @markup.alert.warning) @_link
  (#eq? @_link "[!WARNING]")
  (#set! priority 120))

((shortcut_link
  "[" @markup.alert.caution
  (link_text) @markup.alert.caution
  "]" @markup.alert.caution) @_link
  (#eq? @_link "[!CAUTION]")
  (#set! priority 120))
