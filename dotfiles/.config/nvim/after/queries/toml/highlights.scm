;; extends

;; TOML Table Section Headers -> Solarized Blue (@tag #268BD2)
(table (bare_key) @tag)
(table (dotted_key (bare_key) @tag))
(table (dotted_key (dotted_key (bare_key) @tag)))
(table (dotted_key (dotted_key (dotted_key (bare_key) @tag))))
(table (quoted_key) @tag)
(table (dotted_key (quoted_key) @tag))

(table_array_element (bare_key) @tag)
(table_array_element (dotted_key (bare_key) @tag))
(table_array_element (dotted_key (dotted_key (bare_key) @tag)))
(table_array_element (dotted_key (dotted_key (dotted_key (bare_key) @tag))))
(table_array_element (quoted_key) @tag)
(table_array_element (dotted_key (quoted_key) @tag))

;; TOML Mapping & Inline Keys -> Solarized Green (@property.toml #859900)
(pair (bare_key) @property)
(pair (dotted_key (bare_key) @property))
(pair (dotted_key (dotted_key (bare_key) @property)))
(pair (dotted_key (dotted_key (dotted_key (bare_key) @property))))
(pair (quoted_key) @property)
(pair (dotted_key (quoted_key) @property))

;; TOML Native Date-Time Scalars -> Solarized Magenta (@constant.builtin #D33682)
[
  (local_date)
  (local_date_time)
  (local_time)
  (offset_date_time)
] @constant.builtin
