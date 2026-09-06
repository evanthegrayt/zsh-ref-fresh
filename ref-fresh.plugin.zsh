##
# @file ref-fresh.plugin.zsh
# @brief Plugin-manager entrypoint for Ref Fresh.
# @description
#     Sources `ref-fresh.zsh` from the same directory. Plugin managers commonly
#     load `*.plugin.zsh` files automatically, so this file keeps installation
#     compatible while the implementation lives in `ref-fresh.zsh`.

source "${${(%):-%x}:A:h}/ref-fresh.zsh"
