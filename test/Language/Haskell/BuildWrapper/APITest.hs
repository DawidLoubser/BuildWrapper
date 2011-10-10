{-# LANGUAGE OverloadedStrings #-}
module Language.Haskell.BuildWrapper.APITest where

import Language.Haskell.BuildWrapper.Base
import qualified Language.Haskell.BuildWrapper.API as API
import qualified Language.Haskell.BuildWrapper.Cabal as Cabal
import Language.Haskell.BuildWrapper.Tests


import Test.HUnit

import Control.Monad.State

unitTests :: Test
unitTests=TestList [testGetBuiltPath]

--apiTests::Test
--apiTests=TestList $ map (\f->f DirectAPI) tests
--
--data DirectAPI=DirectAPI
--
--instance APIFacade DirectAPI where
--        synchronize _ r= runAPI r API.synchronize
--        synchronize1 _ r= runAPI r . API.synchronize1
--        write _ r fp s= runAPI r $ API.write fp s
--        configure _ r= runAPI r . API.configure
--        build _ r= runAPI r . API.build
--        getOutline _ r= runAPI r . API.getOutline
--        getTokenTypes _ r= runAPI r . API.getTokenTypes
--        getOccurrences _ r fp s= runAPI r $ API.getOccurrences fp s 
--        getThingAtPoint _ r fp l c q t= runAPI r $ API.getThingAtPoint fp l c q t
--        getNamesInScope _ r= runAPI r . API.getNamesInScope
--        getCabalDependencies _ r= runAPI r . API.getCabalDependencies
--        getCabalComponents _ r= runAPI r . API.getCabalComponents
--
--runAPI:: FilePath -> StateT BuildWrapperState IO a -> IO a
--runAPI root f= do
--        evalStateT f (BuildWrapperState ".dist-buildwrapper" "cabal" (testCabalFile root) Normal "")
   
testGetBuiltPath :: Test
testGetBuiltPath = TestLabel "testGetBuiltPath" (TestCase (do
        assertEqual "backslash path" (Just "src\\Language\\Haskell\\BuildWrapper\\Cabal.hs") $ Cabal.getBuiltPath "[4 of 7] Compiling Language.Haskell.BuildWrapper.Cabal ( src\\Language\\Haskell\\BuildWrapper\\Cabal.hs, dist\\build\\Language\\Haskell\\BuildWrapper\\Cabal.o )"
        assertEqual "forward slash path" (Just "src/Language/Haskell/BuildWrapper/Cabal.hs") $ Cabal.getBuiltPath "[4 of 7] Compiling Language.Haskell.BuildWrapper.Cabal ( src/Language/Haskell/BuildWrapper/Cabal.hs, dist/build/Language/Haskell/BuildWrapper/Cabal.o )"
        assertEqual "no path" Nothing $ Cabal.getBuiltPath "something else"
        ))     