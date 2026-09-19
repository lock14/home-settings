;; extends

; Standard library types and constructors (Date, Object, Math, Promise, Error, etc.)
; remain @type in calm Base0 Grey (#839496) under Pillars I & II, matching TypeScript.
((identifier) @type
  (#any-of? @type
    "Object" "Function" "Symbol" "Number" "Math" "Date" "RegExp" "Map" "Set"
    "WeakMap" "WeakSet" "Promise" "Array" "Error" "EvalError" "InternalError"
    "RangeError" "ReferenceError" "SyntaxError" "TypeError" "URIError"
    "ArrayBuffer" "DataView" "Int8Array" "Uint8Array" "Uint8ClampedArray"
    "Int16Array" "Uint16Array" "Int32Array" "Uint32Array" "Float32Array" "Float64Array")
  (#set! priority 125))

; Built-in global environment singletons (process, globalThis) match console, window, document in Solarized Magenta (#D33682)
((identifier) @variable.builtin
  (#any-of? @variable.builtin "process" "globalThis"))
