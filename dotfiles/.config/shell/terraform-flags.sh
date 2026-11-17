# Shared Terraform CLI and `tf` Completion Flag Tables (Zsh and Bash 3.2+ compatible)
# Pure shell lookup tables with zero subprocess forks.

_HS_TF_ROOT_SUBCMDS="init validate plan apply destroy fmt providers workspace state output import show taint untaint force-unlock graph refresh console get login logout test metadata modules query stacks version -help -version -chdir="

_hs_tf_subcmd_flags() {
    REPLY=""
    case "${1:-}" in
        init)
            REPLY="-backend= -backend-config= -cloud= -force-copy -from-module= -get= -help -ignore-remote-version -input= -json -lock= -lock-timeout= -lockfile= -migrate-state -no-color -plugin-dir= -reconfigure -test-directory= -upgrade -var -var-file="
            ;;
        plan)
            REPLY="-compact-warnings -destroy -detailed-exitcode -generate-config-out= -help -input= -json -lock= -lock-timeout= -no-color -out= -parallelism= -refresh= -refresh-only -replace= -state= -target= -var -var-file="
            ;;
        apply)
            REPLY="-auto-approve -backup= -compact-warnings -destroy -help -input= -json -lock= -lock-timeout= -no-color -parallelism= -refresh= -refresh-only -replace= -state= -state-out= -target= -var -var-file="
            ;;
        destroy)
            REPLY="-auto-approve -backup= -compact-warnings -help -input= -json -lock= -lock-timeout= -no-color -parallelism= -refresh= -refresh-only -replace= -state= -state-out= -target= -var -var-file="
            ;;
        fmt)
            REPLY="-check -diff -help -list= -no-color -recursive -write="
            ;;
        validate)
            REPLY="-help -json -no-color -no-tests -query -test-directory= -var -var-file="
            ;;
        output)
            REPLY="-help -json -no-color -raw -state="
            ;;
        import)
            REPLY="-backup= -config= -help -ignore-remote-version -input= -lock= -lock-timeout= -no-color -state= -state-out= -var -var-file="
            ;;
        refresh)
            REPLY="-backup= -compact-warnings -help -input= -json -lock= -lock-timeout= -no-color -parallelism= -state= -state-out= -target= -var -var-file="
            ;;
        show)
            REPLY="-help -json -no-color"
            ;;
        graph)
            REPLY="-draw-cycles -format= -help -module-depth= -plan= -type= -var -var-file="
            ;;
        console)
            REPLY="-help -plan -scope= -state= -var -var-file="
            ;;
        get)
            REPLY="-help -json -no-color -test-directory= -update -var -var-file="
            ;;
        test)
            REPLY="-cloud-run= -filter= -help -json -junit-xml= -no-color -parallelism= -test-directory= -var -var-file= -verbose"
            ;;
        taint)
            REPLY="-allow-missing -backup= -help -ignore-remote-version -lock= -lock-timeout= -state= -state-out= -var -var-file="
            ;;
        untaint)
            REPLY="-allow-missing -backup= -help -ignore-remote-version -lock= -lock-timeout= -state= -state-out="
            ;;
        force-unlock)
            REPLY="-force -help"
            ;;
        version|"metadata functions"|"workspace list")
            REPLY="-help -json"
            ;;
        "providers schema")
            REPLY="-help -json -no-color -var -var-file="
            ;;
        query)
            REPLY="-generate-config-out= -help -json -no-color -var -var-file="
            ;;
        modules)
            REPLY="-help -json -var -var-file="
            ;;
        providers)
            REPLY="-help -test-directory= -var -var-file="
            ;;
        "providers lock")
            REPLY="-enable-plugin-cache -fs-mirror= -help -net-mirror= -platform= -test-directory= -var -var-file="
            ;;
        "providers mirror")
            REPLY="-help -lock-file= -platform= -var -var-file="
            ;;
        "state list"|"state identities")
            REPLY="-help -id= -state="
            ;;
        "state mv")
            REPLY="-backup= -backup-out= -dry-run -help -ignore-remote-version -lock= -lock-timeout= -state= -state-out= -var -var-file="
            ;;
        "state pull")
            REPLY="-help -var -var-file="
            ;;
        "state push")
            REPLY="-force -help -lock= -lock-timeout= -var -var-file="
            ;;
        "state replace-provider")
            REPLY="-auto-approve -backup= -help -ignore-remote-version -lock= -lock-timeout= -state= -var -var-file="
            ;;
        "state rm")
            REPLY="-backup= -dry-run -help -ignore-remote-version -lock= -lock-timeout= -state= -var -var-file="
            ;;
        "state show")
            REPLY="-help -json -state="
            ;;
        "workspace select")
            REPLY="-help -or-create="
            ;;
        "workspace new")
            REPLY="-help -lock= -lock-timeout= -state="
            ;;
        "workspace delete")
            REPLY="-force -help -lock= -lock-timeout="
            ;;
        stacks)
            REPLY="-chdir= -no-color= -plugin-cache-dir= -stacks-version -usage"
            ;;
        "stacks "*)
            REPLY="-usage"
            ;;
        state|workspace|"workspace show"|metadata|login|logout)
            REPLY="-help"
            ;;
    esac
}

_hs_tf_nested_subcmds() {
    REPLY=""
    case "${1:-}" in
        state)     REPLY="identities list mv pull push replace-provider rm show" ;;
        workspace) REPLY="delete list new select show" ;;
        providers) REPLY="lock mirror schema" ;;
        metadata)  REPLY="functions" ;;
        stacks)    REPLY="init providers-lock validate create list version fmt configuration deployment-group deployment-run deployment-step diagnostics" ;;
    esac
}

_hs_tf_enum_values() {
    REPLY=""
    local flag_name="${1:-}" subcmd="${2:-}"
    case "$flag_name" in
        -backend|-get|-input|-lock|-lock-file|-refresh|-cloud|-list|-write|-or-create)
            REPLY="true false"
            ;;
        -no-color)
            [ "$subcmd" = "stacks" ] && REPLY="true false"
            ;;
        -lockfile)
            REPLY="readonly"
            ;;
        -type)
            [ "$subcmd" = "graph" ] && REPLY="plan plan-refresh-only plan-destroy apply"
            ;;
        -format)
            [ "$subcmd" = "graph" ] && REPLY="dot mermaid"
            ;;
    esac
}
