-- Converged 7-pillar semantic and UI framing highlight group definitions.

local M = {}

function M.build(colors)
    local hl = {
        -- Base canvas and cursor
        Normal = { fg = colors.base0, bg = colors.base03 },
        NormalNC = { fg = colors.base0, bg = colors.base03 },
        Cursor = { fg = colors.base03, bg = colors.base0 },
        CursorLine = { bg = colors.base02 },
        CursorColumn = { bg = colors.base02 },
        ColorColumn = { bg = colors.base02 },
        EndOfBuffer = { fg = colors.base03, bg = "NONE" },
        NonText = { fg = colors.base01 },
        Whitespace = { fg = colors.base01 },
        SpecialKey = { fg = colors.base01 },
        Conceal = { fg = colors.base01 },

        -- Gutter and navigation coordinates (monochromatic luminance)
        LineNr = { fg = colors.base01, bg = colors.base03 },
        LineNrAbove = { fg = colors.base01, bg = colors.base03 },
        LineNrBelow = { fg = colors.base01, bg = colors.base03 },
        CursorLineNr = { fg = colors.base1, bg = colors.base02, bold = true },
        SignColumn = { bg = colors.base03 },
        FoldColumn = { fg = colors.base01, bg = colors.base03 },
        Folded = { fg = colors.base0, bg = colors.base02 },

        -- Window framing and splits (calm Base01 dim borders)
        WinSeparator = { fg = colors.base01, bg = colors.base03 },
        VertSplit = { fg = colors.base01, bg = colors.base03 },
        FloatBorder = { fg = colors.base01, bg = colors.base04 },
        FloatTitle = { fg = colors.base1, bg = colors.base02, bold = true },
        NormalFloat = { fg = colors.base0, bg = colors.base04 },

        -- Mini.files columnar navigator framing
        MiniFilesBorder = { fg = colors.base01, bg = colors.base04 },
        MiniFilesBorderModified = { fg = colors.yellow, bg = colors.base04 },
        MiniFilesCursorLine = { bg = colors.base02 },
        MiniFilesNormal = { fg = colors.base0, bg = colors.base04 },
        MiniFilesTitle = { fg = colors.base01, bg = colors.base02 },
        MiniFilesTitleFocused = { fg = colors.base1, bg = colors.base02, bold = true },

        -- Telescope fuzzy finder framing
        TelescopeNormal = { fg = colors.base0, bg = colors.base04 },
        TelescopeBorder = { fg = colors.base01, bg = colors.base04 },
        TelescopePromptNormal = { fg = colors.base0, bg = colors.base04 },
        TelescopePromptBorder = { fg = colors.base01, bg = colors.base04 },
        TelescopeResultsNormal = { fg = colors.base0, bg = colors.base04 },
        TelescopeResultsBorder = { fg = colors.base01, bg = colors.base04 },
        TelescopePreviewNormal = { fg = colors.base0, bg = colors.base04 },
        TelescopePreviewBorder = { fg = colors.base01, bg = colors.base04 },
        TelescopeTitle = { fg = colors.base1, bg = colors.base02, bold = true },
        TelescopePromptPrefix = { fg = colors.blue, bg = colors.base04 },
        TelescopeSelection = { fg = colors.base1, bg = colors.base02, bold = true },
        TelescopeSelectionCaret = { fg = colors.blue, bg = colors.base02 },
        TelescopeMatching = { fg = colors.yellow, bold = true },

        -- Delimiter matching without syntax mutation
        MatchParen = { fg = colors.base1, bg = colors.base02, bold = true },

        -- Search and selection plane (zero collision)
        Visual = { fg = colors.base1, bg = colors.mix_base1 },
        VisualNOS = { fg = colors.base1, bg = colors.mix_base1 },
        Search = { fg = colors.base1, bg = colors.mix_yellow, bold = true },
        IncSearch = { fg = colors.magenta, bg = colors.mix_magenta, bold = true },
        CurSearch = { fg = colors.magenta, bg = colors.mix_magenta, bold = true },

        -- Messages and status prompts
        Error = { fg = colors.red },
        ErrorMsg = { fg = colors.red },
        WarningMsg = { fg = colors.yellow },
        MoreMsg = { fg = colors.green },
        ModeMsg = { fg = colors.base1, bold = true },
        Question = { fg = colors.cyan },
        Title = { fg = colors.orange, bold = false },
        Todo = { fg = colors.magenta, bg = colors.base02, bold = true },

        -- Status, tabline, and completion menus
        StatusLine = { fg = colors.base1, bg = colors.base04 },
        StatusLineNC = { fg = colors.base01, bg = colors.base04 },
        TabLine = { fg = colors.base01, bg = colors.base04 },
        TabLineFill = { fg = colors.base0, bg = colors.base04 },
        TabLineSel = { fg = colors.base0, bg = colors.base03 },
        Pmenu = { fg = colors.base0, bg = colors.base04 },
        PmenuSel = { fg = colors.base1, bg = colors.base02, bold = true },
        PmenuSbar = { bg = colors.base04 },
        PmenuThumb = { bg = colors.base01 },

        -- Diagnostic signs and sp-only underlines without mutating syntax fg
        DiagnosticSignError = { fg = colors.red, bg = colors.base03 },
        DiagnosticSignWarn = { fg = colors.yellow, bg = colors.base03 },
        DiagnosticSignInfo = { fg = colors.blue, bg = colors.base03 },
        DiagnosticSignHint = { fg = colors.cyan, bg = colors.base03 },
        DiagnosticUnderlineError = { fg = "NONE", sp = colors.red, undercurl = true, underline = true },
        DiagnosticUnderlineWarn = { fg = "NONE", sp = colors.yellow, undercurl = true, underline = true },
        DiagnosticUnderlineInfo = { fg = "NONE", sp = colors.blue, undercurl = true, underline = true },
        DiagnosticUnderlineHint = { fg = "NONE", sp = colors.cyan, undercurl = true, underline = true },

        -- Markup and diff special composite highlights
        ["@spell"] = {},
        ["@markup.strong"] = { fg = colors.base1, bold = true },
        ["@markup.italic"] = { fg = colors.base0, italic = true },
        ["@markup.link"] = { fg = colors.base01, underline = false },
        ["@markup.link.label"] = { fg = colors.blue, underline = false },
        ["@markup.link.url"] = { fg = colors.cyan, underline = false },
        ["@string.special.url.html"] = { fg = colors.cyan, underline = false },
        RenderMarkdownCode = { fg = "NONE", bg = colors.base02 },
        RenderMarkdownCodeBorder = { fg = colors.base01, bg = colors.base02 },
        RenderMarkdownCodeInfo = { fg = colors.base01, bg = colors.base02, italic = false },
        RenderMarkdownCodeFallback = { fg = colors.base0, bg = colors.base02 },
        RenderMarkdownCodeInline = { fg = colors.cyan, bg = colors.base02 },
        RenderMarkdownSign = { fg = colors.base01, bg = "NONE" },
        RenderMarkdownIndent = { fg = colors.base02 },
        RenderMarkdownInlineHighlight = { fg = colors.base1, bg = colors.base02 },
        RenderMarkdownLink = { fg = colors.blue, bold = false, underline = false },
        RenderMarkdownWikiLink = { fg = colors.blue, bold = false, underline = false },
        SnacksImageAnchor = { fg = colors.blue },
        SnacksImageSpinner = { fg = colors.cyan },
        SnacksImageLoading = { fg = colors.base01 },
        SnacksImageMath = { fg = colors.base0 },
        markdownBold = { fg = colors.base1, bold = true },
        markdownItalic = { italic = true },
        markdownLinkText = { fg = colors.blue, underline = false },
        markdownUrl = { fg = colors.cyan, underline = false },
        Added = { fg = colors.green },
        Changed = { fg = colors.yellow },
        Removed = { fg = colors.red },
        DiffAdd = { fg = colors.green, bg = colors.mix_green },
        DiffDelete = { fg = colors.red, bg = colors.mix_red },
        DiffChange = { fg = colors.yellow, bg = colors.mix_yellow },
        DiffText = { fg = colors.blue, bg = colors.mix_blue, bold = true },
        protoTodo = { fg = colors.base01, bg = "NONE", bold = false },
        pbtxtTodo = { fg = colors.base01, bg = "NONE", bold = false },
    }

    local function set_hl(groups, spec)
        for _, g in ipairs(groups) do
            hl[g] = spec
        end
    end

    -- Calm Base0 Grey (#839496): identifiers, invocations, custom types, operators, punctuation
    set_hl({
        "MiniFilesFile", "Type", "Structure", "Identifier", "Operator", "Delimiter", "TagDelimiter",
        "@keyword.conditional.ternary", "@type", "@type.definition", "@type.qualifier", "@constructor",
        "@function.call", "@function.method.call", "@function.builtin", "@variable", "@variable.member",
        "@property", "@operator", "@punctuation.bracket", "@punctuation.delimiter", "@punctuation.special",
        "@tag.delimiter", "@tag.attribute.css", "@markup.raw.xml", "@markup.raw.block",
        "@lsp.type.type", "@lsp.type.class", "@lsp.type.struct", "@lsp.type.interface", "@lsp.type.enum",
        "@lsp.type.typeParameter", "@lsp.type.variable", "@lsp.type.property", "@lsp.typemod.variable.readonly",
        "markdownCodeBlock", "goExtraType", "goType", "rustDeriveTrait", "rustType", "cType", "cppType",
        "shOption", "shCommandSub", "xmlTag", "xmlEndTag", "xmlEqual", "xmlProcessingDelim", "xmlCdata",
        "htmlTag", "htmlEndTag", "htmlHead", "htmlTitle", "cssClassNameDot", "cssUnitizers",
        "cssCustomProperty", "cssVar", "jpropertiesAssignment",
        "@keyword.directive.java", "@type.builtin.terraform", "@type.builtin.hcl",
        "@function.call.terraform", "@function.terraform", "@function.hcl",
        "@markup.heading.html", "@markup.heading.1.html", "@markup.heading.2.html",
        "@markup.heading.3.html", "@markup.heading.4.html", "@markup.heading.5.html", "@markup.heading.6.html",
        "@type.builtin.starlark", "@variable.css", "@function.call.css", "@type.builtin.css",
        "@constant.css", "@variable.properties",
    }, { fg = colors.base0 })

    set_hl({
        "Parameter", "@variable.parameter", "@variable.parameter.builtin", "@markup.quote",
        "@lsp.type.parameter", "markdownBlockquote", "htmlItalic", "@markup.italic.html",
    }, { fg = colors.base0, italic = false })

    set_hl({
        "@markup.heading.5", "@markup.heading.6", "RenderMarkdownH5", "RenderMarkdownH6",
        "markdownH5", "markdownH6", "htmlH1", "htmlH2", "htmlH3", "htmlH4", "htmlH5", "htmlH6",
        "htmlBold", "@markup.strong.html",
    }, { fg = colors.base0, bold = false })

    set_hl({
        "htmlUnderline", "htmlLink", "@markup.link.label.html", "@markup.link.html", "@markup.underline.html",
    }, { fg = colors.base0, underline = false })

    -- Calm Base01 Dim (#586E75): comments, documentation, delimiters, markers, and borders
    set_hl({
        "@label", "@markup.raw.delimiter", "@markup.quote.marker", "@markup.table", "@markup.table.delimiter",
        "RenderMarkdownQuote", "RenderMarkdownQuote1", "RenderMarkdownQuote2", "RenderMarkdownQuote3",
        "RenderMarkdownQuote4", "RenderMarkdownQuote5", "RenderMarkdownQuote6", "RenderMarkdownDash",
        "markdownCodeDelimiter", "diffIndexLine",
    }, { fg = colors.base01 })

    set_hl({
        "Comment", "@string.documentation", "@comment", "@comment.documentation",
        "RenderMarkdownHtmlComment", "@lsp.type.comment", "pythonDocstring", "rustCommentLineDoc",
        "xmlComment", "xmlCommentPart", "htmlComment", "htmlCommentPart", "jpropertiesComment",
        "protoComment", "pbtxtComment",
    }, { fg = colors.base01, italic = false })

    set_hl({
        "@markup.heading.delimiter", "@markup.list.unchecked", "RenderMarkdownTableHead",
        "RenderMarkdownTableRow", "RenderMarkdownTableFill", "RenderMarkdownLinkTitle",
        "RenderMarkdownUnchecked", "markdownHeadingDelimiter", "markdownRule",
    }, { fg = colors.base01, bold = false })

    -- Base1 (#93A1A1) and Base02 (#073642) Markdown headings and backgrounds
    set_hl({ "@markup.heading.4", "RenderMarkdownH4", "markdownH4" }, { fg = colors.base1, bold = false })
    set_hl({
        "RenderMarkdownH1Bg", "RenderMarkdownH2Bg", "RenderMarkdownH3Bg",
        "RenderMarkdownH4Bg", "RenderMarkdownH5Bg", "RenderMarkdownH6Bg",
    }, { fg = "NONE", bg = colors.base02, bold = false })

    -- Solarized Green (#859900): structural scaffolding, primitives, mapping keys, and diff additions
    set_hl({
        "Keyword", "Statement", "StorageClass", "TagAttribute",
        "@keyword", "@keyword.function", "@keyword.modifier", "@keyword.operator", "@keyword.type",
        "@type.builtin", "@tag.attribute", "@markup.alert.tip", "RenderMarkdownBullet", "@lsp.type.keyword",
        "goSignedInts", "goUnsignedInts", "goFloats", "goComplexes", "goDeclaration", "goDeclType",
        "pythonBuiltinType", "rustKeyword", "cStructure", "cStorageClass", "cppAccess", "cppStructure",
        "cppStorageClass", "cppModifier", "diffAdded", "@diff.plus", "shFunctionKey", "sqlKeyword",
        "xmlAttrib", "htmlArg", "cssProp", "jpropertiesIdentifier",
        "protoStructure", "protoRepeat", "protoDefault", "protoExtend", "protoRPC", "protoType",
        "protoTypedef", "pbtxtField", "@attribute.sql",
        "@property.json", "@property.yaml", "@property.toml", "@property.css",
        "@property.properties", "@property.textproto", "@property.pbtxt", "@property.graphql",
    }, { fg = colors.green })

    set_hl({
        "@markup.list", "@markup.list.checked", "RenderMarkdownChecked", "RenderMarkdownSuccess",
        "markdownListMarker", "markdownOrderedListMarker",
    }, { fg = colors.green, bold = false })

    -- Solarized Yellow (#B58900): exclusive imperative control flow and warning diagnostics
    set_hl({
        "DiagnosticWarn", "DiagnosticFloatingWarn", "DiagnosticVirtualTextWarn", "Conditional", "Repeat",
        "@keyword.conditional", "@keyword.repeat", "@keyword.return", "@keyword.coroutine", "@keyword.exception",
        "goStatement", "goConditional", "goRepeat", "pythonConditional", "pythonRepeat",
        "pythonException", "pythonStatement", "rustConditional", "rustRepeat",
        "cConditional", "cRepeat", "cStatement", "diffChanged", "@diff.delta",
        "shConditional", "shRepeat", "shStatement",
    }, { fg = colors.yellow })

    -- Solarized Blue (#268BD2): routine declarations, tags, selectors, H2, and info
    set_hl({
        "Directory", "MiniFilesDirectory", "DiagnosticInfo", "DiagnosticFloatingInfo", "DiagnosticVirtualTextInfo",
        "Function", "Macro", "Tag", "@function", "@function.method", "@function.macro", "@tag",
        "@markup.alert.note", "@lsp.type.function", "@lsp.type.method", "markdownId", "rustMacro",
        "diffLine", "@diff.line", "shFunction", "xmlTagName", "xmlNamespace", "htmlTagName",
        "htmlSpecialTagName", "cssTagName", "cssClassName", "cssIdentifier", "pbtxtMessage",
        "@type.css", "@tag.css",
    }, { fg = colors.blue })

    set_hl({
        "@markup.heading.2", "RenderMarkdownH2", "RenderMarkdownInfo", "markdownH2",
    }, { fg = colors.blue, bold = false })

    -- Solarized Violet (#6C71C4): module imports, namespaces, attributes, H3, and hints
    set_hl({
        "Include", "Special", "@keyword.import", "@module", "@module.builtin", "@markup.alert.important",
        "@attribute", "@lsp.type.namespace", "goDirective", "pythonDecorator", "pythonDecoratorName",
        "rustAttribute", "rustDerive", "rustModPath", "xmlCdataStart", "xmlCdataEnd", "xmlCdataCdata",
        "cssPseudoClass", "cssPseudoClassId", "protoSyntax",
    }, { fg = colors.violet })

    set_hl({
        "@markup.heading.3", "RenderMarkdownH3", "RenderMarkdownMath", "RenderMarkdownHint", "markdownH3",
    }, { fg = colors.violet, bold = false })

    -- Solarized Orange (#CB4B16): preprocessor directives, macros, H1, and alert warnings
    set_hl({
        "PreProc", "Define", "@keyword.directive", "@keyword.directive.define", "@constant.macro",
        "@markup.alert.warning", "cDefine", "cInclude", "cPreProc", "cPreCondit",
        "xmlProcessing", "xmlDocTypeDecl", "xmlDocTypeKeyword", "htmlDoctype", "cssAtRule",
    }, { fg = colors.orange })

    set_hl({
        "@markup.heading", "@markup.heading.1", "RenderMarkdownH1", "RenderMarkdownTodo",
        "RenderMarkdownWarn", "markdownH1",
    }, { fg = colors.orange, bold = false })

    -- Solarized Magenta (#D33682): constants, numbers, booleans, regexes, receivers, and symbols
    set_hl({
        "Constant", "Number", "Boolean", "Float",
        "@variable.builtin", "@string.regexp", "@constant", "@constant.builtin", "@number",
        "@number.float", "@boolean", "@lsp.type.enumMember",
        "goPredefinedIdentifiers", "goConstants", "goDecimalInt", "goHexadecimalInt", "goOctalInt",
        "goFloat", "cConstant", "sqlSpecial", "xmlEntity", "xmlEntityPunct", "htmlSpecialChar",
        "cssColor", "cssValueNumber", "cssValueLength", "protoBool", "protoInt", "protoFloat",
        "pbtxtEnum", "pbtxtBool", "pbtxtInt", "pbtxtHex", "pbtxtFloat", "@variable.builtin.go",
        "@punctuation.delimiter.regex", "@punctuation.bracket.regex", "@operator.regex",
        "@string.escape.regex", "@character.special.regex", "@constant.regex", "@property.regex",
        "@string.special.css", "@string.special.symbol.elixir", "@string.special.symbol.clojure",
        "@string.special.symbol.ruby",
    }, { fg = colors.magenta })

    -- Solarized Cyan (#2AA198): strings, characters, format specifiers, escapes, and diagnostic hints
    set_hl({
        "DiagnosticHint", "DiagnosticFloatingHint", "DiagnosticVirtualTextHint", "String", "Character",
        "@string", "@string.special", "@string.special.path", "@string.special.url",
        "@string.special.symbol", "@string.escape", "@character", "@character.printf",
        "@character.special", "@markup.raw", "@lsp.type.string",
        "markdownCode", "markdownIdDeclaration", "diffFile", "diffNewFile", "xmlString", "htmlString",
        "cssStringQ", "cssStringQQ", "jpropertiesString", "jpropertiesSpecialChar",
        "protoString", "pbtxtString",
    }, { fg = colors.cyan })

    -- Solarized Red (#DC322F): errors, diff deletions, and caution callouts
    set_hl({
        "DiagnosticError", "DiagnosticFloatingError", "DiagnosticVirtualTextError",
        "@markup.alert.caution", "diffRemoved", "@diff.minus", "@keyword.modifier.css",
    }, { fg = colors.red })

    set_hl({ "RenderMarkdownError" }, { fg = colors.red, bold = false })

    return hl
end

return M
