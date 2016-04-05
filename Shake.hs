#!/usr/bin/env stack
{- stack runghc --verbosity info
   --package base-prelude
   --package directory
   --package extra
   --package here
   --package safe
   --package shake
   --package time
   --package pandoc
-}
{-
Usage: see below.
Shake.hs is a more powerful Makefile, providing a number of commands
for performing useful tasks. Compiling this script is suggested, so that
it runs quicker and will not be affected eg when exploring old code versions.
More about Shake: http://shakebuild.com/manual
Requires: https://www.haskell.org/downloads#stack

Shake notes:
notes:
 unclear:
  oracles
 wishlist:
  wildcards in phony rules
  multiple individually accessible wildcards
  just one shake import
-}

{-# LANGUAGE PackageImports, QuasiQuotes #-}

import                Prelude ()
import "base-prelude" BasePrelude
-- import "base"         System.Console.GetOpt
import "extra"        Data.List.Extra
import "here"         Data.String.Here
import "safe"         Safe
import "shake"        Development.Shake
import "shake"        Development.Shake.FilePath
import "time"         Data.Time
import "directory"    System.Directory as S (getDirectoryContents)

usage = [i|Usage:
 ./Shake.hs compile                     # compile this script (optional)
 ./Shake                                # show commands
 ./Shake --help                         # show options
 ./Shake [--color] COMMAND

Commands:
 compile
 manpages
 webmanual
|]

manpages = [
   "hledger_csv.5"
  ,"hledger_journal.5"
  ,"hledger_timedot.5"
  ,"hledger_timelog.5"
  ,"hledger.1"
  ,"hledger-api.1"
  ,"hledger-ui.1"
  ,"hledger-web.1"
  ]

manpageDir p
  | '_' `elem` p = "hledger-lib"
  | otherwise    = dropExtension p

buildDir = ".build"

pandocExe = "stack exec -- pandoc" -- use the pandoc required above

pandocFiltersResolver = ""

main = do

  pandocFilters <-
    map ("tools" </>). nub . sort . map (-<.> "") . filter ("pandoc" `isPrefixOf`)
    <$> S.getDirectoryContents "tools"

  shakeArgs
    shakeOptions{
       shakeFiles=buildDir
      ,shakeVerbosity=Loud
      -- ,shakeReport=[".shake.html"]
      } $ do

    want ["help"]

    phony "help" $ liftIO $ putStrLn usage

    phony "compile" $ need ["Shake"]

    "Shake" %> \out -> do
      need ["Shake.hs"]
      cmd "stack ghc Shake.hs" :: Action ExitCode
      putLoud "Compiled ./Shake, you can now use this instead of ./Shake.hs"

    -- docs

    -- man pages, converted to man nroff with web-only sections removed
    let manpageNroffsForMan = [manpageDir p </> p | p <- manpages]

    -- man pages, still markdown but with man-only sections removed
    -- (we let hakyll do the final markdown rendering)
    let manpageMdsForHakyll = ["site" </> p <.>".md" | p <- manpages]

    phony "manpages" $ need manpageNroffsForMan

    manpageNroffsForMan |%> \out -> do
      let
        md = out <.> "md"
        tmpl = "doc/manpage.nroff"
      need $ md : tmpl : pandocFilters
      cmd pandocExe md "--to man -s --template" tmpl
        "--filter tools/pandocRemoveHtmlBlocks"
        "--filter tools/pandocRemoveHtmlInlines"
        "--filter tools/pandocRemoveLinks"
        "--filter tools/pandocRemoveNotes"
        "--filter tools/pandocCapitalizeHeaders"
        "-o" out

    phony "webmanual" $ need manpageMdsForHakyll

    manpageMdsForHakyll |%> \out -> do
      let
        p = dropExtension $ takeFileName out
        md = manpageDir p </> p <.> "md"
        tmpl = "doc/manpage.html"
      need $ md : tmpl : pandocFilters
      cmd pandocExe md "--to markdown"
        "--filter tools/pandocRemoveManonlyBlocks"
        "-o" out

    phony "pandocfilters" $ need pandocFilters

    pandocFilters |%> \out -> do
      need [out <.> "hs"]
      cmd ("stack "++pandocFiltersResolver++" ghc") out

    -- cleanup

    phony "clean" $ do
      putNormal "Cleaning generated files"
      removeFilesAfter "" manpageNroffsForMan
      removeFilesAfter "" manpageMdsForHakyll
      putNormal "Cleaning object files"
      removeFilesAfter "tools" ["*.o","*.p_o","*.hi"]
      putNormal "Cleaning shake build files"
      removeFilesAfter buildDir ["//*"]

