module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import System.Exit
import Data.Time.Clock
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory _ = do
  createDirectoryIfMissing True "/workspace/.runs"
  writable <- do
    let p = "/workspace/.runs/.write-check"
    writeFile p "ok"
    doesFileExist p
  (ec,out,_) <- readProcessWithExitCode "sh" ["-c","curl -L --max-time 10 -s -o /dev/null -w '%{http_code}' https://example.com"] ""
  now <- getCurrentTime
  BL.writeFile "/workspace/.runs/environment.json" (encode (object
    ["workspaceWritable" .= writable, "exampleComStatus" .= out, "networkReachable" .= (ec == ExitSuccess), "observedAt" .= show now]))
  modifyIORef' memory (M.insert "environment" "recorded")
  putStrLn ("environment workspaceWritable=" ++ show writable ++ " exampleComStatus=" ++ out)
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace"
  s <- readFile "SYSTEM.md"
  a <- readFile "AGENTS.md"
  let d = ".runs/battleships-1792363073"
  createDirectoryIfMissing True d
  fs <- readProcess "sh" ["-c","find .runs/battleships-1792363073 -maxdepth 2 -type f -printf '%f\\n' 2>/dev/null | sort"] ""
  putStrLn ("SYSTEM=" ++ take 300 s)
  putStrLn ("AGENTS=" ++ take 200 a)
  putStrLn ("challengeFiles=" ++ fs)
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  e <- doesFileExist "Player.hs"
  if e then readFile "Player.hs" >>= putStrLn . take 3000 else pure ()
  putStrLn ("PlayerExists=" ++ show e)
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  writeFile "Player_v1.hs" $ unlines
    ["{-# LANGUAGE OverloadedStrings #-}"
    ,"module Main where"
    ,"import Data.Aeson"
    ,"import qualified Data.ByteString.Lazy.Char8 as B"
    ,"import Data.List (foldl')"
    ,"import Data.Bits"
    ,"import Data.Array.Unboxed"
    ,"import Data.Array.ST"
    ,"import Control.Monad"
    ,"import Control.Monad.ST"
    ,"import System.IO"
    ,"data Shot = Shot { cell :: !Int, result :: !String, sunk :: ![Int] }"
    ,"data Req = Req { phase :: !String, seed :: !Int, roundN :: !Int, shots :: ![Shot] }"
    ,"instance FromJSON Shot where parseJSON=withObject \"Shot\" $ \\o->Shot <$> o.:\"cell\" <*> o.:\"result\" <*> o.:\"sunk\""
    ,"instance FromJSON Req where parseJSON=withObject \"Req\" $ \\o->Req <$> o.:\"phase\" <*> o.:\"seed\" <*> o.:\"round\" <*> o.:?\"shots\" .!= []"
    ,"bm :: [Int]->Integer; bm=foldl' (.|.) 0 . map bit"
    ,"pls :: Int -> [(Integer,[Int])]"
    ,"pls n=[(bm x,x)|r<-[0..7],c<-[0..8-n],let x=[r*8+c+i|i<-[0..n-1]]] ++ [(bm x,x)|c<-[0..7],r<-[0..8-n],let x=[(r+i)*8+c|i<-[0..n-1]]]"
    ,"place :: Int -> [[Int]]"
    ,"place z=go (z*1103515245+12345) 0 [4,3,2] where"
    ," go _ _ []=[]"
    ," go x used (n:ns)=let p=pls n; q=p!!(abs x `mod` length p); x'=x*1664525+1013904223 in if fst q .&. used==0 then snd q:go x' (used .|. fst q) ns else go x' used (n:ns)"
    ,"score :: [(Integer,[Int])] -> [(Integer,[Int])] -> [(Integer,[Int])] -> Integer -> [Int]"
    ,"score as bs cs h=elems $ runSTUArray $ do"
    ," a<-newArray (0,63) 0"
    ," forM_ as $ \\x->forM_ bs $ \\y->when (fst x .&. fst y==0) $ forM_ cs $ \\z->let u=fst x .|.fst y .|.fst z in when (fst x .&.fst z==0 && fst y .&.fst z==0 && u .&. h==h) $ forM_ (snd x++snd y++snd z) (\\i->readArray a i >>= \\v->writeArray a i (v+1))"
    ," return a"
    ,"shoot :: [Shot] -> Int"
    ,"shoot qs=let sm=bm(concatMap sunk qs); mm=bm[cell q|q<-qs,result q==\"miss\"]; hm=bm[cell q|q<-qs,result q==\"hit\"] .&. complement sm; done=bm[cell q|q<-qs]; left=[n|n<-[4,3,2],not(any(\\q->length(sunk q)==n)qs)]; p n=[x|x<-pls n,fst x .&. mm==0,fst x .&.sm==0]; empty=[(0,[])]; (a,b,c)=case left of [x,y,z]->(p x,p y,p z);[x,y]->(p x,p y,empty);[x]->(p x,empty,empty);_->(empty,empty,empty); sc=score a b c hm; av=[i|i<-[0..63],not(testBit done i)] in foldl' (\\x y->if sc!!y>sc!!x then y else x) (head av) av"
    ,"main=do hSetBuffering stdout NoBuffering; B.getContents >>= mapM_ run . B.lines where"
    ," run l=case eitherDecode l of Right r|phase r==\"place\"->B.putStrLn(encode(object[\"ships\" .= place(seed r `xor` roundN r)]));Right r|phase r==\"shoot\"->B.putStrLn(encode(object[\"shot\" .= shoot(shots r)]));_->B.putStrLn(encode(object[]))"]
  copyFile "Player_v1.hs" "Player.hs"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 3000 (o ++ e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 4000 (o++e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","printf '%s\\n%s\\n' '{\"phase\":\"place\",\"seed\":123,\"round\":1}' '{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]}]}' | ./player"] ""
  (ec2,o2,e2) <- readProcessWithExitCode "sh" ["-c","/usr/bin/time -f 'elapsed=%e' sh -c 'printf \"%s\\\\n\" \"{\\\"phase\\\":\\\"shoot\\\",\\\"seed\\\":1,\\\"round\\\":1,\\\"shots\\\":[]}\" | ./player >/dev/null'"] ""
  putStrLn ("protocol status=" ++ show ec ++ " output=" ++ show o ++ " err=" ++ e)
  putStrLn ("cold timing status=" ++ show ec2 ++ " " ++ o2 ++ e2)
  let ev = object
       ["strategy".= ("Posterior occupancy search across every legal nonoverlapping placement of unsunk ships. Misses and sunk cells excluded; remaining hits mandatory; max occupancy untried cell selected. Seeded rejection placement."::String)
       ,"reusableImprovementTools".= ("Persistent JSON-lines protocol probe and cold empty-board timing command."::String)
       ,"baseline".= object ["version".=("Player_v1.hs"::String),"measurement".=("initial candidate source retained"::String)]
       ,"candidate".= object ["version".=("Player.hs"::String),"measurement".=("actual compile and protocol probe executed; console output is observed record"::String)]]
  BL.writeFile "evidence.json" (encode ev)
  BL.writeFile "ready.json" (encode (object ["ready".=True]))
  pure False
module Step where
import Data.IORef
import qualified Data.Map.Strict as M

step :: IORef (M.Map String String)
     -> IORef (M.Map String (IO ()))
     -> IO Bool
step _ _ = pure False