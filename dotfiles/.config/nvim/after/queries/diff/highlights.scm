;; extends

;; Ensure deletion and addition markers match the line's diff status
(deletion "-" @diff.minus)
(addition "+" @diff.plus)
(old_file "---" @diff.minus)
(new_file "+++" @diff.plus)

;; Delimiter in index ranges (4b825dc..f1e94a2)
(index ".." @punctuation.delimiter)

;; Hunk range and context section header in Solarized Blue
(location) @diff.line
