" coworkingview.vim - median prices from the CoworkingView Price Index
" Maintainer: CoworkingView <info@coworkingview.com>
" Version: 0.1.0
" License: MIT
" Last Change: 2026 Nov 3

if exists('g:loaded_coworkingview')
  finish
endif
let g:loaded_coworkingview = 1

" {city} is a slug (berlin) or a name (Berlin, Bad Homburg).
" Completion offers slugs from GET /v1/market/rates.
command! -nargs=+ -complete=customlist,coworkingview#complete
      \ CoworkingRate call coworkingview#open(<q-args>)
