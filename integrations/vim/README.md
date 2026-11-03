# coworkingview.vim

Vim plugin for the public [CoworkingView](https://coworkingview.com) Price Index. `:CoworkingRate berlin` fetches `GET https://api.coworkingview.com/v1/market/rates?locale=en` and opens a scratch buffer with the median price of each product published for that city.

There is no API key. The plugin is pure Vimscript (Vim 8.2+ and Neovim) and does not use Python. It does not call the network when it loads. `curl` must be on `$PATH`. Neovim runs curl through `system()` with an argument list. Vim 8.2 runs the same list through `job_start()`, because `system()` there always invokes a shell.

The Price Index is **CC BY 4.0**. The scratch buffer ends with the `attribution` string from the response. Keep that line with any figure you copy. The plugin code is MIT; the data is not.

Source: <https://github.com/coworkingview/flex-office-data>

## Install

Unzip `coworkingview-vim-0.1.0.zip` so `plugin/`, `autoload/` and `doc/` land in `~/.vim` (or `~/vimfiles` on Windows):

```text
~/.vim/plugin/coworkingview.vim
~/.vim/autoload/coworkingview.vim
~/.vim/doc/coworkingview.txt
```

Then `:helptags ~/.vim/doc`.

vim-plug, from this repository:

```vim
Plug 'coworkingview/flex-office-data', {'rtp': 'integrations/vim'}
```

## Usage

```vim
:CoworkingRate berlin
:CoworkingRate Berlin
```

`<Tab>` completes city slugs from the API. A city name works too (`Bad Homburg`). The buffer lists `product`, `unit`, `median`, `sample_size` and `low_confidence` (`true` when `sample_size` is below 10). `unit` is `month` for a monthly product, `day` for a day pass and `hour` for a meeting room.

A successful response stays in memory for 10 minutes (`g:coworkingview_cache_seconds`). On HTTP 429 or 5xx the plugin waits and tries once more.

```vim
let g:coworkingview_api_url = 'https://api.coworkingview.com'
let g:coworkingview_locale = 'en'
let g:coworkingview_cache_seconds = 600
let g:coworkingview_curl = 'curl'
```

`$COWORKINGVIEW_API_URL` overrides the host when `g:coworkingview_api_url` is unset. The user agent is `coworkingview-vim/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.

`:help coworkingview` covers the command and the options.

## Tests

From the repository root, with [vader.vim](https://github.com/junegunn/vader.vim) and [vint](https://github.com/Vimjas/vint):

```bash
vint integrations/vim/plugin integrations/vim/autoload
bash integrations/vim/test/run.sh
```

`VIM_BIN=nvim bash integrations/vim/test/run.sh` runs the same file under Neovim. The tests use a curl stand-in and `spec/fixtures/market_rates.json`. They do not touch the network.

## Release zip

```bash
bash integrations/vim/build.sh
```

This writes `dist/coworkingview-vim-0.1.0.zip`. The archive root is `plugin/`, `autoload/`, `doc/`, `README.md` and `LICENSE`. Fields for a vim.org upload are in `VIMORG.md`.
