{-# LANGUAGE CPP,OverloadedStrings,PatternGuards #-}
module Language.Haskell.BuildWrapper.UsagesTests where

import Language.Haskell.BuildWrapper.Base

import Language.Haskell.BuildWrapper.Tests
import Language.Haskell.BuildWrapper.CMDTests
import Test.HUnit

import System.Directory
import System.FilePath

import System.Time

import qualified Data.ByteString.Lazy as BS
-- import qualified Data.ByteString.Lazy.Char8 as BSC (putStrLn)
import qualified Data.ByteString as BSS
import Data.Aeson
import Data.Maybe

import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.HashMap.Lazy as HM
import qualified Data.Vector as V

usageTests::[Test]
usageTests= map (\f->f CMDAPI) utests

utests :: (APIFacade a)=> [a -> Test]
utests= [-- testGenerateASTCreatesBWUsage,
        testGenerateReferencesSimple --,
       -- testGenerateReferencesImports,
        --testGenerateReferencesExports
        ]

testGenerateASTCreatesBWUsage :: (APIFacade a)=> a -> Test
testGenerateASTCreatesBWUsage api= TestLabel "testGenerateASTCreatesBWUsage" (TestCase ( do
        root<-createTestProject
        ((fps,dels),_)<-synchronize api root False
        assertBool "no file path on creation" (not $ null fps)
        assertBool "deletions" (null dels)  
        assertEqual "no cabal file" (testProjectName <.> ".cabal") (head fps)
        let rel="src" </> "A.hs"
        assertBool "no A" (rel `elem` fps)
        let bwI1=getUsageFile (root </> ".dist-buildwrapper" </>  rel)
        ef1<-doesFileExist bwI1
        assertBool (bwI1 ++ "  file exists before build") (not ef1)
        (BuildResult bool1 fps1,nsErrors1)<-build api root False Source
        assertBool "returned false on bool1" bool1
        assertBool "no errors or warnings on nsErrors1" (null nsErrors1)
        assertBool ("no rel in fps1: " ++ show fps1) (rel `elem` fps1)
        assertBool (bwI1 ++ "  file exists after build") (not ef1)
        (comps,_)<-getCabalComponents api root
        c1<-getClockTime
        mapM_ (generateAST api root) comps
        c2<-getClockTime
        putStrLn ("generateAST: " ++ timeDiffToString (diffClockTimes c2 c1))
        ef2<-doesFileExist bwI1
        assertBool (bwI1 ++ " file doesn't exist after generateAST") ef2
        ))

testGenerateReferencesSimple :: (APIFacade a)=> a -> Test
testGenerateReferencesSimple api= TestLabel "testGenerateReferencesSimple" (TestCase ( do
        root<-createTestProject
        let relMain="src"</>"Main.hs"
        writeFile (root</> relMain) $ unlines [  
                  "module Main where",
                  "import A",
                  "main=print $ reset $ Cons2 1"
                  ] 
        let rel="src" </> "A.hs"
        writeFile (root</> rel) $ unlines [  
                  "module A where",
                  "data MyData=Cons1", 
                  "      { mdS::MyString}", 
                  "      | Cons2 Int",
                  "     deriving Show",
                  "",
                  "type MyString=String",
                  "",
                  "reset :: MyData -> MyData",
                  "reset (Cons1 _)=Cons1 \"\"",
                  "reset (Cons2 _)=Cons2 0",
                  "",
                  "resetAll=map reset",
                  "",
                  "getString :: MyData -> Maybe MyString",
                  "getString (Cons1 s)=Just s",
                  "getString _= Nothing"
                  ]  
        _<-synchronize api root True          
        (BuildResult bool1 _,nsErrors1)<-build api root False Source
        assertBool ("returned false on bool1:" ++ show nsErrors1)  bool1
        assertBool "no errors or warnings on nsErrors1" (null nsErrors1)
        (comps,_)<-getCabalComponents api root    
        mapM_ (generateAST api root) comps
        --sI<-fmap formatJSON (readFile  $ getInfoFile(root </> ".dist-buildwrapper" </>  rel))
        --putStrLn sI
        v<-readStoredUsage (root </> ".dist-buildwrapper" </>  rel)
        sU<-fmap formatJSON (readFile  $ getUsageFile(root </> ".dist-buildwrapper" </>  rel))
        putStrLn sU
      
        assertPackageModule "BWTest-0.1" "A" v
      
        assertVarUsage "BWTest-0.1" "A" "Cons1" [[2,13,2,18],[10,8,10,13],[10,17,10,22],[16,12,16,17]] v
        assertVarUsage "BWTest-0.1" "A" "Cons2" [[4,9,4,14],[11,8,11,13],[11,17,11,22]] v
        assertVarUsage "BWTest-0.1" "A" "mdS" [[3,9,3,12]] v
        assertVarUsage "BWTest-0.1" "A" "reset" [[9,1,9,6],[10,1,10,25],[11,1,11,24],[13,14,13,19]] v
        assertVarUsage "BWTest-0.1" "A" "resetAll" [[13,1,13,19]] v
        assertVarUsage "BWTest-0.1" "A" "getString" [[15,1,15,10],[16,1,16,27],[17,1,17,21]] v
        assertVarUsage "base" "Data.Maybe" "Nothing" [[17,14,17,21]] v
        assertVarUsage "base" "Data.Maybe" "Just" [[16,21,16,25]] v
        assertVarUsage "base" "GHC.Base" "map" [[13,10,13,13]] v
        assertVarUsage "base" "GHC.Num" "fromInteger" [[11,23,11,24]] v
        
        assertTypeUsage "BWTest-0.1" "A" "MyData" [[2,6,2,12],[9,10,9,16],[9,20,9,26],[15,14,15,20]] v
        assertTypeUsage "BWTest-0.1" "A" "MyString" [[3,14,3,22],[7,6,7,14],[15,30,15,38]] v
        assertTypeUsage "base" "Data.Maybe" "Maybe" [[15,24,15,29]] v
        assertTypeUsage "base" "GHC.Base" "String" [[7,15,7,21]] v
        assertTypeUsage "base" "GHC.Show" "Show" [[5,15,5,19]] v
        assertTypeUsage "ghc-prim" "GHC.Types" "Int" [[4,15,4,18]] v
        
        vMain<-readStoredUsage (root </> ".dist-buildwrapper" </>  relMain)
        --sUMain<-fmap formatJSON (readFile  $ getUsageFile(root </> ".dist-buildwrapper" </>  relMain))
        --putStrLn sUMain
        assertPackageModule "BWTest-0.1" "Main" vMain
        
        assertVarUsage "BWTest-0.1" "A" "" [[2,8,2,9]] vMain
        assertVarUsage "BWTest-0.1" "A" "Cons2" [[3,22,3,27]] vMain
        assertVarUsage "BWTest-0.1" "A" "reset" [[3,14,3,19]] vMain
        assertVarUsage "BWTest-0.1" "Main" "main" [[3,1,3,29]] vMain
        assertVarUsage "base" "System.IO" "print" [[3,6,3,11]] vMain
        assertVarUsage "base" "GHC.Base" "$" [[3,12,3,13],[3,20,3,21]] vMain
        return ()
        ))

testGenerateReferencesImports :: (APIFacade a)=> a -> Test
testGenerateReferencesImports api= TestLabel "testGenerateReferencesImports" (TestCase ( do
        root<-createTestProject
        let relMain="src"</>"Main.hs"
        writeFile (root</> relMain) $ unlines [
                  "module Main where",
                  "import Data.Ord",
                  "import Data.Maybe (Maybe(..))",
                  "import Data.Complex (Complex((:+)))",
                  "",
                  "main=undefined"
                  ] 
        _<-synchronize api root True          
        (BuildResult bool1 _,nsErrors1)<-build api root False Source
        assertBool ("returned false on bool1:" ++ show nsErrors1)  bool1
        assertBool "no errors or warnings on nsErrors1" (null nsErrors1)
        (comps,_)<-getCabalComponents api root    
        mapM_ (generateAST api root) comps
        vMain<-readStoredUsage (root </> ".dist-buildwrapper" </>  relMain)
        -- sUMain<-fmap formatJSON (readFile  $ getUsageFile(root </> ".dist-buildwrapper" </>  relMain))
        -- putStrLn sUMain
        assertVarUsage "base" "Data.Ord" "" [[2,8,2,16]] vMain
        assertVarUsage "base" "Data.Maybe" "" [[3,8,3,18]] vMain
        assertVarUsage "base" "Data.Complex" "" [[4,8,4,20]] vMain
        assertTypeUsage "base" "Data.Maybe" "Maybe" [[3,20,3,29]] vMain
        assertTypeUsage "base" "Data.Complex" "Complex" [[4,22,4,35]] vMain
        assertVarUsage "base" "Data.Complex" ":+" [[4,22,4,35]] vMain
        ))

testGenerateReferencesExports :: (APIFacade a)=> a -> Test
testGenerateReferencesExports api= TestLabel "testGenerateReferencesExports" (TestCase ( do
        root<-createTestProject
        let rel="src" </> "A.hs"
        writeFile (root</> rel) $ unlines [  
                  "module A (",
                  "    MyData,",
                  "    MyData2(..),",
                  "    MyData3(Cons31),",
                  "    reset,",
                  "    MyString,",
                  "    module Data.Ord) where",
                  "import Data.Ord",
                  "data MyData=Cons1", 
                  "      { mdS::MyString}", 
                  "      | Cons2 Int",
                  "     deriving Show",
                  "",
                  "type MyString=String",
                  "",
                  "reset :: MyData -> MyData",
                  "reset (Cons1 _)=Cons1 \"\"",
                  "reset (Cons2 _)=Cons2 0",
                  "",
                  "data MyData2=Cons21", 
                  "      { mdS2::MyString}", 
                  "      | Cons22 Int",
                  "     deriving Show",
                  "data MyData3=Cons31", 
                  "      { mdS3::MyString}", 
                  "      | Cons32 Int",
                  "     deriving Show"
                  ]  
        _<-synchronize api root True          
        (BuildResult bool1 _,nsErrors1)<-build api root False Source
        assertBool ("returned false on bool1:" ++ show nsErrors1)  bool1
        assertBool "no errors or warnings on nsErrors1" (null nsErrors1)
        (comps,_)<-getCabalComponents api root    
        mapM_ (generateAST api root) comps
        v<-readStoredUsage (root </> ".dist-buildwrapper" </>  rel)
        --sU<-fmap formatJSON (readFile  $ getUsageFile(root </> ".dist-buildwrapper" </>  rel))
        --putStrLn sU
        
        assertVarUsage "BWTest-0.1" "A" "Cons1" [[9,13,9,18],[17,8,17,13],[17,17,17,22]] v
        assertVarUsage "BWTest-0.1" "A" "Cons2" [[11,9,11,14],[18,8,18,13],[18,17,18,22]] v
        assertVarUsage "BWTest-0.1" "A" "Cons21" [[20,14,20,20]] v
        assertVarUsage "BWTest-0.1" "A" "Cons22" [[22,9,22,15]] v
        assertVarUsage "BWTest-0.1" "A" "Cons31" [[4,5,4,20],[24,14,24,20]] v
        assertVarUsage "BWTest-0.1" "A" "Cons32" [[26,9,26,15]] v
        assertVarUsage "BWTest-0.1" "A" "mdS" [[10,9,10,12]] v
        assertVarUsage "BWTest-0.1" "A" "mdS2" [[21,9,21,13]] v
        assertVarUsage "BWTest-0.1" "A" "mdS3" [[25,9,25,13]] v
        assertVarUsage "BWTest-0.1" "A" "reset" [[5,5,5,10],[16,1,16,6],[17,1,17,25],[18,1,18,24]] v
        assertVarUsage "base" "GHC.Num" "fromInteger" [[18,23,18,24]] v
        
        assertVarUsage "base" "Data.Ord" "" [[7,5,7,20],[8,8,8,16]] v
        
        assertTypeUsage "BWTest-0.1" "A" "MyData" [[2,5,2,11],[9,6,9,12],[16,10,16,16],[16,20,16,26]] v
        assertTypeUsage "BWTest-0.1" "A" "MyString" [[6,5,6,13],[10,14,10,22],[14,6,14,14],[21,15,21,23],[25,15,25,23]] v
        assertTypeUsage "base" "GHC.Base" "String" [[14,15,14,21]] v
        assertTypeUsage "base" "GHC.Show" "Show" [[12,15,12,19],[23,15,23,19],[27,15,27,19]] v
        assertTypeUsage "BWTest-0.1" "A" "MyData2" [[3,5,3,16],[20,6,20,13]] v
        assertTypeUsage "BWTest-0.1" "A" "MyData3" [[4,5,4,20],[24,6,24,13]] v
        assertTypeUsage "ghc-prim" "GHC.Types" "Int" [[11,15,11,18],[22,16,22,19],[26,16,26,19]] v
        ))        
        
getUsageFile :: FilePath -- ^ the source file
        -> FilePath
getUsageFile fp= let 
        (dir,file)=splitFileName fp
        in combine dir ('.' : addExtension file ".bwusage")      
        
readStoredUsage :: FilePath  -- ^ the source file
        -> IO Value
readStoredUsage =readJSONFile . getUsageFile

  
readJSONFile :: FilePath -> IO Value
readJSONFile f= do
       ex<-doesFileExist f
       mv<-if ex
                then do
                       bs<-BSS.readFile f
                       return $ decode' $ BS.fromChunks [bs]
                else return Nothing
       return $ fromMaybe (object []) mv
       
getInfoFile :: FilePath -- ^ the source file
        -> FilePath
getInfoFile fp= let 
        (dir,file)=splitFileName fp
        in combine dir ('.' : addExtension file ".bwinfo")      
        
-- | read the top JSON value containing all the information
readStoredInfo :: FilePath  -- ^ the source file
        -> IO Value
readStoredInfo =readJSONFile . getInfoFile 

extractNameValue :: Value -> T.Text
extractNameValue (Object m) |Just (String s)<-HM.lookup "Name" m=s
extractNameValue _ = error "no name in value"

assertVarUsage :: T.Text -> T.Text -> T.Text -> [[Int]] -> Value -> IO() 
assertVarUsage = assertUsage "vars"

assertTypeUsage :: T.Text -> T.Text -> T.Text -> [[Int]] -> Value -> IO() 
assertTypeUsage = assertUsage "types"


assertUsage :: T.Text -> T.Text -> T.Text -> T.Text -> [[Int]] -> Value -> IO()
assertUsage tp pkg modu name lins (Array v) |
        V.length v==3,
        (Object m) <-v V.! 2,
        Just (Object m2)<-HM.lookup pkg m,
        Just (Object m3)<-HM.lookup modu m2,
        Just (Object m4)<-HM.lookup tp m3,
        Just (Array arr)<-HM.lookup name m4=   do
                let expected=S.fromList $ map (\[sl,sc,el,ec]->InFileSpan (InFileLoc sl sc) (InFileLoc el ec)) lins
                let actual=S.fromList $ map (\v->let (Success ifl)=fromJSON v in ifl) $ V.toList arr
                assertEqual (T.unpack modu ++ "." ++ T.unpack name ++ ": " ++ show lins) expected actual  
        --V.elem (Number (I line)) arr=return ()
assertUsage _ _ modu name line _=assertBool (T.unpack modu ++ "." ++ T.unpack name ++ ": " ++ show line) False

assertPackageModule :: T.Text -> T.Text -> Value -> IO()
assertPackageModule pkg modu (Array v) |
         V.length v==3,
        (String s0) <-v V.! 0,
        (String s1) <-v V.! 1= do
                assertEqual (T.unpack pkg) pkg s0
                assertEqual (T.unpack modu) modu s1    
assertPackageModule pkg modu _=  assertBool (T.unpack pkg ++ "." ++ T.unpack modu) False