;; extends

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
