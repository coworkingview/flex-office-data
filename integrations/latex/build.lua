#!/usr/bin/env texlua
-- Build script for the coworkingview LaTeX package.
-- l3build check runs testfiles/*.lvt. l3build ctan writes coworkingview.zip
-- with a single top-level coworkingview/ directory.

module = "coworkingview"
ctanpkg = "coworkingview"
ctanzip = "coworkingview"

sourcefiles = {"coworkingview.sty", "coworkingview-rates.csv"}
installfiles = {"coworkingview.sty", "coworkingview-rates.csv"}
typesetfiles = {"coworkingview-doc.tex"}
textfiles = {"README.md", "LICENSE"}

flatten = true
packtdszip = false
typesetruns = 2

checkengines = {"pdftex"}
stdengine = "pdftex"
checkformat = "latex"

-- Keep the committed documentation PDF. The default clean list deletes *.pdf.
cleanfiles = {
  "*.log",
  "*.aux",
  "*.toc",
  "*.out",
  "*.synctex.gz",
  "*.hd",
  "*.fls",
  "*.fdb_latexmk",
}

excludefiles = {"*~", "build.lua", "config-*.lua", ".*"}
