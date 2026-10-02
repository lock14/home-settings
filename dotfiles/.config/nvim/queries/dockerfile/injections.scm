; Dockerfile language injections (isolated per shell_command without file-wide injection.combined)
; Prevents multi-RUN bash LanguageTree nodes from spanning across intermediate Dockerfile instructions.

((comment) @injection.content
  (#set! injection.language "comment"))

((shell_command) @injection.content
  (#set! injection.language "bash")
  (#set! injection.include-children))

((run_instruction
  (heredoc_block) @injection.content)
  (#set! injection.language "bash")
  (#set! injection.include-children))
