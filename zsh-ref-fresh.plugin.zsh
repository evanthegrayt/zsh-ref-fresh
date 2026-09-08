##
# @file zsh-ref-fresh.plugin.zsh
# @brief Plugin-manager entrypoint for Ref Fresh.
# @description
#     Sources `zsh-ref-fresh.zsh` from the same directory. Plugin managers commonly
#     load `*.plugin.zsh` files automatically, so this file keeps installation
#     compatible while the implementation lives in `zsh-ref-fresh.zsh`.

source "${${(%):-%x}:A:h}/zsh-ref-fresh.zsh"
