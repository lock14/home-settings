;; extends

; Unify all decorators (including @property, @classmethod, @staticmethod) as @attribute (Solarized Orange #cb4b16)
((decorator
  (identifier) @attribute)
  (#set! priority 110))

; In Python, def __init__ is a method definition matching all other def declarations.
; Keep method definitions consistently Solarized Blue (@function.method #268bd2).
((class_definition
  (block
    (function_definition
      name: (identifier) @function.method)))
  (#set! priority 110))
