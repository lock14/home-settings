"""Open-source Bazel Starlark rules and macros for telemetry schema codegen.

Demonstrates load() statements (@bazel_skylib, @rules_cc), custom providers,
rule implementations, ctx.actions.run(), transitive depsets, attr schemas,
and platform-aware macros using select().
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:defs.bzl", "CcInfo", "cc_library", "cc_test")

DEFAULT_COPTS = ["-Wall", "-Wextra", "-Werror", "-std=c++20"]
MAX_SCHEMA_FILES = 64

TelemetrySchemaInfo = provider(
    doc = "Propagates direct and transitive telemetry schema descriptors.",
    fields = {
        "direct_sources": "List of direct schema files for this target.",
        "transitive_sources": "Depset of transitive schema files from deps.",
        "wire_format": "Negotiated wire encoding version string.",
    },
)

def _telemetry_schema_library_impl(ctx):
    """Rule implementation generating C++ headers from telemetry schemas."""
    if not ctx.files.srcs:
        fail("srcs attribute must not be empty for target %s" % ctx.label)
    if len(ctx.files.srcs) > MAX_SCHEMA_FILES:
        fail("target %s exceeds MAX_SCHEMA_FILES (%d)" % (ctx.label, MAX_SCHEMA_FILES))

    generated_hdrs = []
    for src in ctx.files.srcs:
        stem = paths.replace_extension(src.basename, "")
        out_hdr = ctx.actions.declare_file(stem + ".telemetry.h", sibling = src)
        ctx.actions.run(
            inputs = [src],
            outputs = [out_hdr],
            executable = ctx.executable._codegen_tool,
            arguments = [
                "--format=" + ctx.attr.wire_format,
                "--out=" + out_hdr.path,
                src.path,
            ],
            mnemonic = "TelemetryCodegen",
            progress_message = "Generating telemetry C++ header for %{input}",
        )
        generated_hdrs.append(out_hdr)

    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [
            dep[TelemetrySchemaInfo].transitive_sources
            for dep in ctx.attr.deps
            if TelemetrySchemaInfo in dep
        ],
    )

    return [
        DefaultInfo(files = depset(generated_hdrs)),
        TelemetrySchemaInfo(
            direct_sources = ctx.files.srcs,
            transitive_sources = transitive_srcs,
            wire_format = ctx.attr.wire_format,
        ),
    ]

telemetry_schema_library = rule(
    doc = "Compiles declarative telemetry schemas into C++20 header descriptors.",
    implementation = _telemetry_schema_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".proto", ".graphql"],
            mandatory = True,
            doc = "Source schema files to compile.",
        ),
        "deps": attr.label_list(
            providers = [TelemetrySchemaInfo],
            default = [],
            doc = "Upstream telemetry_schema_library dependencies.",
        ),
        "wire_format": attr.string(
            default = "v2",
            values = ["v1", "v2"],
            doc = "Wire format revision emitted by the code generator.",
        ),
        "_codegen_tool": attr.label(
            default = Label("//tools/codegen:telemetry_codegen"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [TelemetrySchemaInfo],
)

def telemetry_cc_library(
        name,
        srcs,
        hdrs = [],
        deps = [],
        copts = DEFAULT_COPTS,
        enable_tests = True,
        visibility = ["//visibility:public"],
        **kwargs):
    """Macro defining a telemetry C++ library and optional unit test target."""
    platform_copts = select({
        "@platforms//os:linux": ["-DTELEMETRY_OS_LINUX=1", "-pthread"],
        "@platforms//os:macos": ["-DTELEMETRY_OS_MACOS=1"],
        "//conditions:default": [],
    })

    cc_library(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        copts = copts + platform_copts,
        visibility = visibility,
        **kwargs
    )

    if enable_tests:
        cc_test(
            name = name + "_test",
            size = "small",
            srcs = srcs,
            deps = [":" + name] + deps,
            copts = copts + platform_copts,
            visibility = ["//visibility:private"],
        )
