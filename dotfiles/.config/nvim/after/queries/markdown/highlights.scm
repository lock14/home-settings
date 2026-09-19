;; extends

; ATX Heading Delimiters (#, ##, ###, ...) -> Solarized Base01
[
  (atx_h1_marker)
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
] @markup.heading.delimiter

; Blockquote Markers (>, >>, ...) -> Solarized Base01
[
  (block_quote_marker)
  (block_continuation)
] @markup.quote.marker

; Thematic Break (---) -> Solarized Base01
(thematic_break) @markup.table.delimiter

; Table Delimiters, Delimiter Cells (| and :---:), and Table Header Cells (Base1)
(pipe_table_header
  "|" @markup.table.delimiter)

(pipe_table_header
  (pipe_table_cell) @markup.heading.4)

(pipe_table_row
  "|" @markup.table.delimiter)

(pipe_table_delimiter_row
  "|" @markup.table.delimiter)

(pipe_table_delimiter_cell) @markup.table.delimiter

; Fenced Code Block Delimiters (```, ~~~) and Language Annotations -> Solarized Base01
(fenced_code_block
  (fenced_code_block_delimiter) @markup.raw.delimiter)

(fenced_code_block
  (info_string
    (language) @markup.raw.delimiter))

(fenced_code_block
  (info_string) @markup.raw.delimiter)
