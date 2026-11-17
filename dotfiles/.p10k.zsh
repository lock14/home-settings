# Powerlevel10k Single-Line Solarized Dark Prompt Configuration
# Modularized: VCS & PR hyperlink engine in ~/.config/shell/p10k-vcs.zsh,
# monorepo project-scoping hooks in ~/.config/shell/p10k-segments.zsh,
# and machine-local overrides in ~/.config/zsh/p10k.local.zsh.

'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  unset -m '(POWERLEVEL9K_*|DEFAULT_USER|_HS_P10K_BASE_*)~POWERLEVEL9K_GITSTATUS_DIR'

  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon                 # os identifier
    dir                     # current directory
    vcs                     # git status
    # prompt_char           # prompt symbol
  )

  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code of the last command
    command_execution_time  # duration of the last command
    background_jobs         # presence of background jobs
    direnv                  # direnv status (https://direnv.net/)
    asdf                    # asdf version manager (https://github.com/asdf-vm/asdf)
    virtualenv              # python virtual environment (https://docs.python.org/3/library/venv.html)
    anaconda                # conda environment (https://conda.io/)
    pyenv                   # python environment (https://github.com/pyenv/pyenv)
    goenv                   # go environment (https://github.com/syndbg/goenv)
    nodenv                  # node.js version from nodenv (https://github.com/nodenv/nodenv)
    nvm                     # node.js version from nvm (https://github.com/nvm-sh/nvm)
    nodeenv                 # node.js environment (https://github.com/ekalinin/nodeenv)
    node_version            # node.js version
    go_version              # go version (https://golang.org)
    rust_version            # rustc version (https://www.rust-lang.org)
    java_version            # java version (https://www.java.com/)
    package                 # name@version from package.json (https://docs.npmjs.com/files/package.json)
    rbenv                   # ruby version from rbenv (https://github.com/rbenv/rbenv)
    rvm                     # ruby version from rvm (https://rvm.io)
    fvm                     # flutter version management (https://github.com/leoafarias/fvm)
    luaenv                  # lua version from luaenv (https://github.com/cehoffman/luaenv)
    jenv                    # java version from jenv (https://github.com/jenv/jenv)
    plenv                   # perl version from plenv (https://github.com/tokuhirom/plenv)
    perlbrew                # perl version from perlbrew (https://github.com/gugod/App-perlbrew)
    phpenv                  # php version from phpenv (https://github.com/phpenv/phpenv)
    scalaenv                # scala version from scalaenv (https://github.com/scalaenv/scalaenv)
    haskell_stack           # haskell version from stack (https://haskellstack.org/)
    kubecontext             # current kubernetes context (https://kubernetes.io/)
    terraform               # terraform workspace (https://www.terraform.io)
    terraform_version       # terraform version (https://www.terraform.io)
    aws                     # aws profile (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
    aws_eb_env              # aws elastic beanstalk environment (https://aws.amazon.com/elasticbeanstalk/)
    azure                   # azure account name (https://docs.microsoft.com/en-us/cli/azure)
    gcloud                  # google cloud cli account and project (https://cloud.google.com/)
    google_app_cred         # google application credentials (https://cloud.google.com/docs/authentication/production)
    toolbox                 # toolbox name (https://github.com/containers/toolbox)
    context                 # user@hostname
    nordvpn                 # nordvpn connection status, linux only (https://nordvpn.com/)
    ranger                  # ranger shell (https://github.com/ranger/ranger)
    nnn                     # nnn shell (https://github.com/jarun/nnn)
    lf                      # lf shell (https://github.com/gokcehan/lf)
    xplr                    # xplr shell (https://github.com/sayanarijit/xplr)
    vim_shell               # vim shell indicator (:sh)
    midnight_commander      # midnight commander shell (https://midnight-commander.org/)
    nix_shell               # nix shell (https://nixos.org/nixos/nix-pills/developing-with-nix-shell.html)
    vi_mode                 # vi mode (you don't need this if you've enabled prompt_char)
    todo                    # todo items (https://github.com/todotxt/todo.txt-cli)
    timewarrior             # timewarrior tracking status (https://timewarrior.net/)
    taskwarrior             # taskwarrior task count (https://taskwarrior.org/)
  )

  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  typeset -g POWERLEVEL9K_ICON_PADDING=none

  typeset -g POWERLEVEL9K_GO_ICON=$'\uE627'            # Solid filled Gopher silhouette (replaces hollow E626)
  typeset -g POWERLEVEL9K_TERRAFORM_ICON=$'\uF1BB'     # Terraform BMP icon in MesloLGS NF
  typeset -g POWERLEVEL9K_NODE_ICON=$'\uE718'          # Official Node.js hexagon badge with JS (replaces small arch E617)
  typeset -g POWERLEVEL9K_NODEJS_ICON=$'\uE718'
  typeset -g POWERLEVEL9K_RUBY_ICON=$'\uE791'          # Official faceted Ruby gemstone (replaces diamond outline F219)
  typeset -g POWERLEVEL9K_JAVA_ICON=$'\uF0F4'          # Solid filled coffee mug with saucer (replaces squished E738)

  typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=

  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX='%F{#586E75}╭─'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX='%F{#586E75}├─'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%F{#586E75}╰─'
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX='%F{#586E75}─╮'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX='%F{#586E75}─┤'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX='%F{#586E75}─╯'

  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_BACKGROUND=
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_GAP_BACKGROUND=
  if [[ $POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR != ' ' ]]; then
    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND='#586E75'
    typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_FIRST_SEGMENT_END_SYMBOL='%{%}'
    typeset -g POWERLEVEL9K_EMPTY_LINE_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL='%{%}'
  fi

  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR='%F{#657B83}\uE0B1'
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR='%F{#657B83}\uE0B3'
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR='\uE0B0'
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR='\uE0B2'
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL='\uE0B0'
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL='\uE0B2'
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=

  #################################[ os_icon: os identifier ]##################################
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND='#839496'
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND='#073642'

  ################################[ prompt_char: prompt symbol ]################################
  typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_{LEFT,RIGHT}_WHITESPACE=

  ##################################[ dir: current directory ]##################################
  typeset -g POWERLEVEL9K_DIR_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_DIR_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=false
  local anchor_files=(
    .bzr
    .git
    .hg
    .node-version
    .python-version
    .go-version
    .ruby-version
    .lua-version
    .java-version
    .perl-version
    .php-version
    .tool-version
    .shorten_folder_marker
    .svn
    .terraform
    .terraform.lock.hcl
    .terraform-version
    CVS
    Cargo.toml
    composer.json
    go.mod
    package.json
    stack.yaml
  )
  typeset -g POWERLEVEL9K_SHORTEN_FOLDER_MARKER="(${(j:|:)anchor_files})"
  typeset -g POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=false
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS=40
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT=50
  typeset -g POWERLEVEL9K_DIR_HYPERLINK=false

  typeset -g POWERLEVEL9K_DIR_SHOW_WRITABLE=v3

  #####################################[ vcs: git status ]######################################
  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND='#586E75'
  typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_VCS_BRANCH_ICON='\uF126 '

  typeset -g POWERLEVEL9K_VCS_UNTRACKED_ICON='?'

  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1

  typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN='~'

  typeset -g POWERLEVEL9K_DISABLE_GITSTATUS=true
  (( $+functions[gitstatus_stop_p9k_] )) && gitstatus_stop_p9k_ POWERLEVEL9K
  unset _p9k_preinit
  unfunction _p9k_preinit instant_prompt_vcs 2>/dev/null
  zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null
  typeset -g POWERLEVEL9K_VCS_HYPERLINK=true

  # Load modular Git VCS + PR hyperlink engine and monorepo toolchain scoping hooks.
  local _hs_p10k_shell_dir="${${(%):-%x}:A:h}/.config/shell"
  if [[ ! -d $_hs_p10k_shell_dir ]]; then
    if [[ -n ${_HS_SHELL_DIR:-} && -d $_HS_SHELL_DIR ]]; then
      _hs_p10k_shell_dir=$_HS_SHELL_DIR
    elif [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/shell ]]; then
      _hs_p10k_shell_dir=${XDG_CONFIG_HOME:-$HOME/.config}/shell
    elif [[ -d $HOME/.config/shell ]]; then
      _hs_p10k_shell_dir=$HOME/.config/shell
    fi
  fi
  if [[ -d $_hs_p10k_shell_dir ]]; then
    typeset -g _HS_SHELL_DIR=$_hs_p10k_shell_dir
    [[ -r $_hs_p10k_shell_dir/p10k-vcs.zsh ]] && source $_hs_p10k_shell_dir/p10k-vcs.zsh
    [[ -r $_hs_p10k_shell_dir/p10k-segments.zsh ]] && source $_hs_p10k_shell_dir/p10k-segments.zsh
  fi

  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${P9K_CONTENT}'
  typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED,CONFLICTED,COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=-1

  typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)

  ##########################[ status: exit code of the last command ]###########################
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true

  typeset -g POWERLEVEL9K_STATUS_OK=true
  typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='✔'
  typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_STATUS_OK_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_STATUS_OK_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_VISUAL_IDENTIFIER_EXPANSION='✔'
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='✘'
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL=true
  typeset -g POWERLEVEL9K_STATUS_VERBOSE_SIGNAME=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION='✘'
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_VISUAL_IDENTIFIER_EXPANSION='✘'
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_BACKGROUND='#073642'

  ###################[ command_execution_time: duration of the last command ]###################
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'

  #######################[ background_jobs: presence of background jobs ]#######################
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false

  #######################[ direnv: direnv status (https://direnv.net/) ]########################
  typeset -g POWERLEVEL9K_DIRENV_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_DIRENV_BACKGROUND='#073642'

  ###############[ asdf: asdf version manager (https://github.com/asdf-vm/asdf) ]###############
  typeset -g POWERLEVEL9K_ASDF_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_ASDF_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_SOURCES=(shell local global)

  typeset -g POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW=false

  typeset -g POWERLEVEL9K_ASDF_SHOW_SYSTEM=true

  typeset -g POWERLEVEL9K_ASDF_SHOW_ON_UPGLOB=

  typeset -g POWERLEVEL9K_ASDF_RUBY_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_ASDF_RUBY_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_PYTHON_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_ASDF_PYTHON_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_GOLANG_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_ASDF_GOLANG_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_NODEJS_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_ASDF_NODEJS_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_RUST_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_ASDF_RUST_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_DOTNET_CORE_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_ASDF_DOTNET_CORE_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_FLUTTER_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_ASDF_FLUTTER_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_LUA_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_ASDF_LUA_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_JAVA_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_ASDF_JAVA_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_PERL_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_ASDF_PERL_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_ERLANG_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_ASDF_ERLANG_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_ELIXIR_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_ASDF_ELIXIR_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_POSTGRES_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_ASDF_POSTGRES_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_PHP_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_ASDF_PHP_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_HASKELL_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_ASDF_HASKELL_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ASDF_JULIA_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_ASDF_JULIA_BACKGROUND='#073642'

  ##########[ nordvpn: nordvpn connection status, linux only (https://nordvpn.com/) ]###########
  typeset -g POWERLEVEL9K_NORDVPN_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_NORDVPN_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_NORDVPN_{DISCONNECTED,CONNECTING,DISCONNECTING}_CONTENT_EXPANSION=
  typeset -g POWERLEVEL9K_NORDVPN_{DISCONNECTED,CONNECTING,DISCONNECTING}_VISUAL_IDENTIFIER_EXPANSION=

  #################[ ranger: ranger shell (https://github.com/ranger/ranger) ]##################
  typeset -g POWERLEVEL9K_RANGER_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_RANGER_BACKGROUND='#073642'

  ######################[ nnn: nnn shell (https://github.com/jarun/nnn) ]#######################
  typeset -g POWERLEVEL9K_NNN_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_NNN_BACKGROUND='#073642'

  ######################[ lf: lf shell (https://github.com/gokcehan/lf) ]#######################
  typeset -g POWERLEVEL9K_LF_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_LF_BACKGROUND='#073642'

  ##################[ xplr: xplr shell (https://github.com/sayanarijit/xplr) ]##################
  typeset -g POWERLEVEL9K_XPLR_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_XPLR_BACKGROUND='#073642'

  ###########################[ vim_shell: vim shell indicator (:sh) ]###########################
  typeset -g POWERLEVEL9K_VIM_SHELL_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_VIM_SHELL_BACKGROUND='#073642'

  ######[ midnight_commander: midnight commander shell (https://midnight-commander.org/) ]######
  typeset -g POWERLEVEL9K_MIDNIGHT_COMMANDER_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_MIDNIGHT_COMMANDER_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_NIX_SHELL_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_NIX_SHELL_BACKGROUND='#073642'

  ##################################[ disk_usage: disk usage ]##################################
  typeset -g POWERLEVEL9K_DISK_USAGE_NORMAL_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_DISK_USAGE_NORMAL_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_DISK_USAGE_WARNING_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_DISK_USAGE_WARNING_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_DISK_USAGE_CRITICAL_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_DISK_USAGE_CRITICAL_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL=90
  typeset -g POWERLEVEL9K_DISK_USAGE_CRITICAL_LEVEL=95
  typeset -g POWERLEVEL9K_DISK_USAGE_ONLY_WARNING=false

  ###########[ vi_mode: vi mode (you don't need this if you've enabled prompt_char) ]###########
  typeset -g POWERLEVEL9K_VI_MODE_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_VI_MODE_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VI_COMMAND_MODE_STRING=NORMAL
  typeset -g POWERLEVEL9K_VI_MODE_NORMAL_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VI_VISUAL_MODE_STRING=VISUAL
  typeset -g POWERLEVEL9K_VI_MODE_VISUAL_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_VI_MODE_VISUAL_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VI_OVERWRITE_MODE_STRING=OVERTYPE
  typeset -g POWERLEVEL9K_VI_MODE_OVERWRITE_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_VI_MODE_OVERWRITE_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VI_INSERT_MODE_STRING=
  typeset -g POWERLEVEL9K_VI_MODE_INSERT_FOREGROUND='#586E75'

  ######################################[ ram: free RAM ]#######################################
  typeset -g POWERLEVEL9K_RAM_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_RAM_BACKGROUND='#073642'

  #####################################[ swap: used swap ]######################################
  typeset -g POWERLEVEL9K_SWAP_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_SWAP_BACKGROUND='#073642'

  ######################################[ load: CPU load ]######################################
  typeset -g POWERLEVEL9K_LOAD_WHICH=5
  typeset -g POWERLEVEL9K_LOAD_NORMAL_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_LOAD_NORMAL_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_LOAD_WARNING_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_LOAD_WARNING_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_LOAD_CRITICAL_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_LOAD_CRITICAL_BACKGROUND='#073642'

  ################[ todo: todo items (https://github.com/todotxt/todo.txt-cli) ]################
  typeset -g POWERLEVEL9K_TODO_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_TODO_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_TODO_HIDE_ZERO_TOTAL=true
  typeset -g POWERLEVEL9K_TODO_HIDE_ZERO_FILTERED=false

  ###########[ timewarrior: timewarrior tracking status (https://timewarrior.net/) ]############
  typeset -g POWERLEVEL9K_TIMEWARRIOR_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_TIMEWARRIOR_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_TIMEWARRIOR_CONTENT_EXPANSION='${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+'$'\u2026''}'

  ##############[ taskwarrior: taskwarrior task count (https://taskwarrior.org/) ]##############
  typeset -g POWERLEVEL9K_TASKWARRIOR_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_TASKWARRIOR_BACKGROUND='#073642'

  ################################[ cpu_arch: CPU architecture ]################################
  typeset -g POWERLEVEL9K_CPU_ARCH_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_CPU_ARCH_BACKGROUND='#073642'

  ##################################[ context: user@hostname ]##################################
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_CONTEXT_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'

  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

  ###[ virtualenv: python virtual environment (https://docs.python.org/3/library/venv.html) ]###
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_VIRTUALENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=false
  typeset -g POWERLEVEL9K_VIRTUALENV_{LEFT,RIGHT}_DELIMITER=

  #####################[ anaconda: conda environment (https://conda.io/) ]######################
  typeset -g POWERLEVEL9K_ANACONDA_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_ANACONDA_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_ANACONDA_CONTENT_EXPANSION='${${${${CONDA_PROMPT_MODIFIER#\(}% }%\)}:-${CONDA_PREFIX:t}}'

  ################[ pyenv: python environment (https://github.com/pyenv/pyenv) ]################
  typeset -g POWERLEVEL9K_PYENV_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_PYENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_PYENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_PYENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_PYENV_SHOW_SYSTEM=true

  typeset -g POWERLEVEL9K_PYENV_CONTENT_EXPANSION='${P9K_CONTENT}${${P9K_CONTENT:#$P9K_PYENV_PYTHON_VERSION(|/*)}:+ $P9K_PYENV_PYTHON_VERSION}'

  ################[ goenv: go environment (https://github.com/syndbg/goenv) ]################
  typeset -g POWERLEVEL9K_GOENV_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_GOENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_GOENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_GOENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_GOENV_SHOW_SYSTEM=true

  ##########[ nodenv: node.js version from nodenv (https://github.com/nodenv/nodenv) ]##########
  typeset -g POWERLEVEL9K_NODENV_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_NODENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_NODENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_NODENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_NODENV_SHOW_SYSTEM=true

  ##############[ nvm: node.js version from nvm (https://github.com/nvm-sh/nvm) ]###############
  typeset -g POWERLEVEL9K_NVM_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_NVM_BACKGROUND='#073642'

  ############[ nodeenv: node.js environment (https://github.com/ekalinin/nodeenv) ]############
  typeset -g POWERLEVEL9K_NODEENV_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_NODEENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_NODEENV_SHOW_NODE_VERSION=false
  typeset -g POWERLEVEL9K_NODEENV_{LEFT,RIGHT}_DELIMITER=

  ##############################[ node_version: node.js version ]###############################
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_NODE_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_NODE_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\uE718'

  #######################[ go_version: go version (https://golang.org) ]########################
  typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_GO_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_GO_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_GO_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\uE627'

  #################[ rust_version: rustc version (https://www.rust-lang.org) ]##################
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_RUST_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true

  ###############[ dotnet_version: .NET version (https://dotnet.microsoft.com) ]################
  typeset -g POWERLEVEL9K_DOTNET_VERSION_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_DOTNET_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_DOTNET_VERSION_PROJECT_ONLY=true

  #####################[ php_version: php version (https://www.php.net/) ]######################
  typeset -g POWERLEVEL9K_PHP_VERSION_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_PHP_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_PHP_VERSION_PROJECT_ONLY=true

  ##########[ laravel_version: laravel php framework version (https://laravel.com/) ]###########
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_BACKGROUND='#073642'

  #############[ rbenv: ruby version from rbenv (https://github.com/rbenv/rbenv) ]##############
  typeset -g POWERLEVEL9K_RBENV_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_RBENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_RBENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_RBENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_RBENV_SHOW_SYSTEM=true
  typeset -g POWERLEVEL9K_RBENV_VISUAL_IDENTIFIER_EXPANSION=$'\uE791'

  ####################[ java_version: java version (https://www.java.com/) ]####################
  typeset -g POWERLEVEL9K_JAVA_VERSION_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_JAVA_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_JAVA_VERSION_FULL=false
  typeset -g POWERLEVEL9K_JAVA_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\uF0F4'

  ###[ package: name@version from package.json (https://docs.npmjs.com/files/package.json) ]####
  typeset -g POWERLEVEL9K_PACKAGE_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_PACKAGE_BACKGROUND='#073642'

  #######################[ rvm: ruby version from rvm (https://rvm.io) ]########################
  typeset -g POWERLEVEL9K_RVM_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_RVM_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_RVM_SHOW_GEMSET=false
  typeset -g POWERLEVEL9K_RVM_SHOW_PREFIX=false
  typeset -g POWERLEVEL9K_RVM_VISUAL_IDENTIFIER_EXPANSION=$'\uE791'

  ###########[ fvm: flutter version management (https://github.com/leoafarias/fvm) ]############
  typeset -g POWERLEVEL9K_FVM_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_FVM_BACKGROUND='#073642'

  ##########[ luaenv: lua version from luaenv (https://github.com/cehoffman/luaenv) ]###########
  typeset -g POWERLEVEL9K_LUAENV_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_LUAENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_LUAENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_LUAENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_LUAENV_SHOW_SYSTEM=true

  ###############[ jenv: java version from jenv (https://github.com/jenv/jenv) ]################
  typeset -g POWERLEVEL9K_JENV_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_JENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_JENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_JENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_JENV_SHOW_SYSTEM=true

  ###########[ plenv: perl version from plenv (https://github.com/tokuhirom/plenv) ]############
  typeset -g POWERLEVEL9K_PLENV_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_PLENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_PLENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_PLENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_PLENV_SHOW_SYSTEM=true

  ###########[ perlbrew: perl version from perlbrew (https://github.com/gugod/App-perlbrew) ]############
  typeset -g POWERLEVEL9K_PERLBREW_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_PERLBREW_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_PERLBREW_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_PERLBREW_SHOW_PREFIX=false

  ############[ phpenv: php version from phpenv (https://github.com/phpenv/phpenv) ]############
  typeset -g POWERLEVEL9K_PHPENV_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_PHPENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_PHPENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_PHPENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_PHPENV_SHOW_SYSTEM=true

  #######[ scalaenv: scala version from scalaenv (https://github.com/scalaenv/scalaenv) ]#######
  typeset -g POWERLEVEL9K_SCALAENV_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_SCALAENV_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_SCALAENV_SOURCES=(shell local global)
  typeset -g POWERLEVEL9K_SCALAENV_PROMPT_ALWAYS_SHOW=false
  typeset -g POWERLEVEL9K_SCALAENV_SHOW_SYSTEM=true

  ##########[ haskell_stack: haskell version from stack (https://haskellstack.org/) ]###########
  typeset -g POWERLEVEL9K_HASKELL_STACK_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_HASKELL_STACK_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_HASKELL_STACK_SOURCES=(shell local)
  typeset -g POWERLEVEL9K_HASKELL_STACK_ALWAYS_SHOW=true

  ################[ terraform: terraform workspace (https://www.terraform.io) ]#################
  typeset -g POWERLEVEL9K_TERRAFORM_SHOW_DEFAULT=false
  typeset -g POWERLEVEL9K_TERRAFORM_CLASSES=(
      '*'         OTHER)
  typeset -g POWERLEVEL9K_TERRAFORM_OTHER_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_TERRAFORM_OTHER_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_TERRAFORM_OTHER_VISUAL_IDENTIFIER_EXPANSION=$'\U000F1062'

  #############[ terraform_version: terraform version (https://www.terraform.io) ]##############
  typeset -g POWERLEVEL9K_TERRAFORM_VERSION_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_TERRAFORM_VERSION_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_TERRAFORM_VERSION_SHOW_ON_COMMAND='terraform|tf'
  typeset -g POWERLEVEL9K_TERRAFORM_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\U000F1062'

  #############[ kubecontext: current kubernetes context (https://kubernetes.io/) ]#############
  typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens|kubectx|oc|istioctl|kogito|k9s|helmfile|flux|fluxctl|stern|kubeseal|skaffold|kubent|kubecolor'

  typeset -g POWERLEVEL9K_KUBECONTEXT_CLASSES=(
      '*'       DEFAULT)
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION=
  POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION+='${P9K_KUBECONTEXT_CLOUD_CLUSTER:-${P9K_KUBECONTEXT_NAME}}'
  POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION+='${${:-/$P9K_KUBECONTEXT_NAMESPACE}:#/default}'

  typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|awless|terraform|pulumi|terragrunt'

  typeset -g POWERLEVEL9K_AWS_CLASSES=(
      '*'       DEFAULT)
  typeset -g POWERLEVEL9K_AWS_DEFAULT_FOREGROUND='#CB4B16'
  typeset -g POWERLEVEL9K_AWS_DEFAULT_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_AWS_CONTENT_EXPANSION='${P9K_AWS_PROFILE//\%/%%}${P9K_AWS_REGION:+ ${P9K_AWS_REGION//\%/%%}}'

  typeset -g POWERLEVEL9K_AWS_EB_ENV_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_AWS_EB_ENV_BACKGROUND='#073642'

  ##########[ azure: azure account name (https://docs.microsoft.com/en-us/cli/azure) ]##########
  typeset -g POWERLEVEL9K_AZURE_SHOW_ON_COMMAND='az|terraform|pulumi|terragrunt'
  typeset -g POWERLEVEL9K_AZURE_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_AZURE_BACKGROUND='#073642'

  ##########[ gcloud: google cloud account and project (https://cloud.google.com/) ]###########
  typeset -g POWERLEVEL9K_GCLOUD_SHOW_ON_COMMAND='gcloud|gcs|gsutil'
  typeset -g POWERLEVEL9K_GCLOUD_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_GCLOUD_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_GCLOUD_PARTIAL_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_ID//\%/%%}'
  typeset -g POWERLEVEL9K_GCLOUD_COMPLETE_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_NAME//\%/%%}'

  typeset -g POWERLEVEL9K_GCLOUD_REFRESH_PROJECT_NAME_SECONDS=60

  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_SHOW_ON_COMMAND='terraform|pulumi|terragrunt'

  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES=(
      '*'             DEFAULT)
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_CONTENT_EXPANSION='${P9K_GOOGLE_APP_CRED_PROJECT_ID//\%/%%}'

  ##############[ toolbox: toolbox name (https://github.com/containers/toolbox) ]###############
  typeset -g POWERLEVEL9K_TOOLBOX_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_TOOLBOX_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_TOOLBOX_CONTENT_EXPANSION='${P9K_TOOLBOX_NAME:#fedora-toolbox-*}'

  ###############################[ public_ip: public IP address ]###############################
  typeset -g POWERLEVEL9K_PUBLIC_IP_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_PUBLIC_IP_BACKGROUND='#073642'

  ########################[ vpn_ip: virtual private network indicator ]#########################
  typeset -g POWERLEVEL9K_VPN_IP_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_VPN_IP_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_VPN_IP_CONTENT_EXPANSION=
  typeset -g POWERLEVEL9K_VPN_IP_INTERFACE='(gpd|wg|(.*tun)|tailscale)[0-9]*|(zt.*)'
  typeset -g POWERLEVEL9K_VPN_IP_SHOW_ALL=false

  ###########[ ip: ip address and bandwidth usage for a specified network interface ]###########
  typeset -g POWERLEVEL9K_IP_FOREGROUND='#2AA198'
  typeset -g POWERLEVEL9K_IP_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_IP_CONTENT_EXPANSION='${P9K_IP_RX_RATE:+'$'\u21E3''$P9K_IP_RX_RATE }${P9K_IP_TX_RATE:+'$'\u21E1''$P9K_IP_TX_RATE }$P9K_IP_IP'
  typeset -g POWERLEVEL9K_IP_INTERFACE='[ew].*'

  #########################[ proxy: system-wide http/https/ftp proxy ]##########################
  typeset -g POWERLEVEL9K_PROXY_FOREGROUND='#6C71C4'
  typeset -g POWERLEVEL9K_PROXY_BACKGROUND='#073642'

  ################################[ battery: internal battery ]#################################
  typeset -g POWERLEVEL9K_BATTERY_LOW_THRESHOLD=20
  typeset -g POWERLEVEL9K_BATTERY_LOW_FOREGROUND='#DC322F'
  typeset -g POWERLEVEL9K_BATTERY_{CHARGING,CHARGED}_FOREGROUND='#859900'
  typeset -g POWERLEVEL9K_BATTERY_DISCONNECTED_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_BATTERY_STAGES='\UF008E\UF007A\UF007B\UF007C\UF007D\UF007E\UF007F\UF0080\UF0081\UF0082\UF0079'
  typeset -g POWERLEVEL9K_BATTERY_VERBOSE=false
  typeset -g POWERLEVEL9K_BATTERY_BACKGROUND='#073642'

  #####################################[ wifi: wifi speed ]#####################################
  typeset -g POWERLEVEL9K_WIFI_FOREGROUND='#268BD2'
  typeset -g POWERLEVEL9K_WIFI_BACKGROUND='#073642'

  ####################################[ time: current time ]####################################
  typeset -g POWERLEVEL9K_TIME_FOREGROUND='#93A1A1'
  typeset -g POWERLEVEL9K_TIME_BACKGROUND='#073642'
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false

  function prompt_example() {
    p10k segment -b 1 -f 3 -i $'\uF005' -t 'hello, %n'
  }

  function instant_prompt_example() {
    prompt_example
  }

  typeset -g POWERLEVEL9K_EXAMPLE_FOREGROUND='#B58900'
  typeset -g POWERLEVEL9K_EXAMPLE_BACKGROUND='#073642'

  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always

  typeset -g POWERLEVEL9K_INSTANT_PROMPT=verbose

  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # Snapshot pristine POWERLEVEL9K_* defaults before theme and machine-local overrides run so
  # subsequent in-place theme switches restore clean baselines without duplicating local appends.
  typeset -gA _HS_P10K_BASE_SCALARS=() _HS_P10K_BASE_ARRAYS=()
  local _hs_bp
  local -a _hs_bp_arr
  for _hs_bp in ${(k)parameters[(I)POWERLEVEL9K_*]}; do
    [[ $_hs_bp == POWERLEVEL9K_GITSTATUS_DIR || $_hs_bp == POWERLEVEL9K_CONFIG_FILE ]] && continue
    case ${(Pt)_hs_bp} in
      scalar*) _HS_P10K_BASE_SCALARS[$_hs_bp]=${(P)_hs_bp} ;;
      array*)
        _hs_bp_arr=( "${(@P)_hs_bp}" )
        if (( ${#_hs_bp_arr} == 0 )); then
          _HS_P10K_BASE_ARRAYS[$_hs_bp]=$'\x01EMPTY\x01'
        else
          _HS_P10K_BASE_ARRAYS[$_hs_bp]=${(pj:\0:)_hs_bp_arr}
        fi
        ;;
    esac
  done

  # Active color theme overrides (managed by bin/theme).
  local p10k_theme=${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/p10k-theme.zsh
  [[ -r $p10k_theme ]] && source $p10k_theme

  # Machine-local overrides that stay out of this repository (e.g. extra directory anchors or
  # workdirs to skip VCS status in). The untracked file runs here, after the defaults above and
  # before reload, so `typeset -g POWERLEVEL9K_*` settings in it are re-applied on every source.
  local p10k_local=${XDG_CONFIG_HOME:-$HOME/.config}/zsh/p10k.local.zsh
  [[ -r $p10k_local ]] && source $p10k_local

  # If p10k is already loaded, reload configuration.
  # This works even with POWERLEVEL9K_DISABLE_HOT_RELOAD=true.
  (( ! $+functions[p10k] )) || p10k reload
}

# Tell `p10k configure` which file it should overwrite.
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'

# Eliminate the 1-character space between right prompt and the edge of the screen.
# Must be set after prompt expansion (${(%):-%x}) above, which resets ZLE_RPROMPT_INDENT to 1.
typeset -g ZLE_RPROMPT_INDENT=0
