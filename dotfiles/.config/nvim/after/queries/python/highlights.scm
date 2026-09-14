;; extends

; Unify all decorators (including @property, @classmethod, @staticmethod) as @attribute (Solarized Violet #6c71c4)
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

; Special dunder attributes (e.g. func.__name__, cls.__doc__, obj.__class__)
; are Solarized Magenta (@constant.builtin #d33682)
((attribute
  attribute: (identifier) @constant.builtin)
  (#lua-match? @constant.builtin "^__[a-zA-Z0-9_]+__$")
  (#set! priority 120))

; Built-in exceptions (ValueError, KeyError, etc.) remain @type in calm Base0 (#839496)
((identifier) @type
  (#any-of? @type
    "BaseException" "Exception" "ArithmeticError" "BufferError" "LookupError" "AssertionError"
    "AttributeError" "EOFError" "FloatingPointError" "GeneratorExit" "ImportError"
    "ModuleNotFoundError" "IndexError" "KeyError" "KeyboardInterrupt" "MemoryError" "NameError"
    "NotImplementedError" "OSError" "OverflowError" "RecursionError" "ReferenceError" "RuntimeError"
    "StopIteration" "StopAsyncIteration" "SyntaxError" "IndentationError" "TabError" "SystemError"
    "SystemExit" "TypeError" "UnboundLocalError" "UnicodeError" "UnicodeEncodeError"
    "UnicodeDecodeError" "UnicodeTranslateError" "ValueError" "ZeroDivisionError" "EnvironmentError"
    "IOError" "WindowsError" "BlockingIOError" "ChildProcessError" "ConnectionError"
    "BrokenPipeError" "ConnectionAbortedError" "ConnectionRefusedError" "ConnectionResetError"
    "FileExistsError" "FileNotFoundError" "InterruptedError" "IsADirectoryError" "NotADirectoryError"
    "PermissionError" "ProcessLookupError" "TimeoutError" "Warning" "UserWarning" "DeprecationWarning"
    "PendingDeprecationWarning" "SyntaxWarning" "RuntimeWarning" "FutureWarning" "ImportWarning"
    "UnicodeWarning" "BytesWarning" "ResourceWarning")
  (#set! priority 125))


