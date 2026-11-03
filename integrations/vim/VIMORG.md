# vim.org script upload

Paste these fields into the vim.org script form (https://www.vim.org/scripts/). The description is plain text.

## Script name

coworkingview

## Script type

utility

## Summary

Median CoworkingView Price Index prices for one city.

## Description

coworkingview is a Vim plugin that shows median flexible-office prices for one city from the CoworkingView Price Index. :CoworkingRate berlin opens a scratch buffer with the median price of each product the index publishes for that city (flex desk, fixed desk, private office, day pass, meeting room, and any other product in the response), plus the sample size. Tab completion offers city slugs from the same request.

The plugin calls one public endpoint, GET https://api.coworkingview.com/v1/market/rates?locale=en. There is no API key and no account. It is pure Vimscript and runs on Vim 8.2 or newer and on Neovim. curl must be on PATH. Nothing is downloaded when the plugin loads.

The Price Index is CC BY 4.0. The scratch buffer ends with the attribution line returned by the API. Keep that line when you copy a figure.

Website: https://coworkingview.com
Source: https://github.com/coworkingview/flex-office-data

## Install details

Requires Vim 8.2+ or Neovim, and curl on PATH. No Python.

Download coworkingview-vim-0.1.0.zip and unzip it into ~/.vim on Unix or ~/vimfiles on Windows. The archive root contains plugin/, autoload/ and doc/ (plus README.md and LICENSE). Start Vim and run:

  :helptags ~/.vim/doc

Then:

  :CoworkingRate berlin

Press Tab after the command to complete a city slug. :help coworkingview explains the buffer and the options.

To install from the source repository instead of the zip, point your package manager at integrations/vim. With vim-plug:

  Plug 'coworkingview/flex-office-data', {'rtp': 'integrations/vim'}

## Upload file

coworkingview-vim-0.1.0.zip

The zip root is the plugin directories (plugin/, autoload/, doc/) plus README.md and LICENSE. It is built by integrations/vim/build.sh and published as a CI artifact under the same file name. A copy is committed at integrations/vim/dist/coworkingview-vim-0.1.0.zip when the archive is under 50KB.
