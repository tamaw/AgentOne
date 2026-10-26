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
  w <- doesDirectoryExist "/workspace"
  (ec,_,_) <- readProcessWithExitCode "sh" ["-c","curl -L --max-time 10 -s -o /dev/null -w '%{http_code}' https://example.com"] ""
  t <- getCurrentTime
  let val = object ["workspaceWritable" .= w, "exampleCom" .= (ec == ExitSuccess), "observedAt" .= show t]
  BL.writeFile "/workspace/.runs/environment.json" (encode val)
  ag <- readFile "/workspace/AGENTS.md"
  putStrLn ("environment: workspaceWritable=" ++ show w ++ ", exampleCom=" ++ show (ec == ExitSuccess))
  putStrLn ("AGENTS.md read: " ++ take 120 (filter (/= '\n') ag))
  modifyIORef' memory (M.insert "environment" "recorded")
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import System.Exit
import Control.Monad

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace"
  sys <- readFile "SYSTEM.md"
  putStrLn ("SYSTEM: " ++ take 500 sys)
  let d = ".runs/battleships-1792363073"
  createDirectoryIfMissing True d
  xs <- listDirectory d
  putStrLn ("challenge files: " ++ show xs)
  (ec,out,err) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc --version"] ""
  putStrLn ("ghc check: " ++ show ec ++ " " ++ take 300 (out ++ err))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import Control.Monad

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  (ec,out,err) <- readProcessWithExitCode "sh" ["-c","find . -maxdepth 3 -type f -printf '%p\\n' | sort"] ""
  putStrLn ("files:\n" ++ out ++ err)
  (ec2,o2,e2) <- readProcessWithExitCode "sh" ["-c","find /workspace -maxdepth 3 -type f \\( -iname '*battle*' -o -iname '*trace*' \\) -printf '%p\\n' | sort"] ""
  putStrLn ("trace candidates:\n" ++ o2 ++ e2)
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  writeFile "Player_v1.hs" $ unlines
    ["{-# LANGUAGE OverloadedStrings #-}"
    ,"module Main where"
    ,"import Data.Aeson"
    ,"import qualified Data.ByteString.Lazy.Char8 as B"
    ,"import qualified Data.Vector as V"
    ,"import Data.List (foldl', sort)"
    ,"import Data.Bits"
    ,"import System.IO"
    ,"data Req = Req { phase :: String, seed :: Int, roundN :: Int, shots :: [Shot] }"
    ,"data Shot = Shot { cell :: Int, result :: String, sunk :: [Int] }"
    ,"instance FromJSON Shot where parseJSON = withObject \"Shot\" $ \\o -> Shot <$> o .: \"cell\" <*> o .: \"result\" <*> o .: \"sunk\""
    ,"instance FromJSON Req where parseJSON = withObject \"Req\" $ \\o -> Req <$> o .: \"phase\" <*> o .: \"seed\" <*> o .: \"round\" <*> o .:? \"shots\" .!= []"
    ,"bitc :: Int -> Integer; bitc x = bit x"
    ,"mask :: [Int] -> Integer; mask = foldl' (.|.) 0 . map bitc"
    ,"placements :: Int -> [(Integer,[Int])]"
    ,"placements n = [ (mask cs,cs) | r <- [0..7], c <- [0..7], (dr,dc) <- [(0,1),(1,0)], let cs=[(r+i*dr)*8+c+i*dc|i<-[0..n-1]], all (<64) cs, let cols=map (`mod` 8) cs, maximum cols-minimum cols == (n-1)*dc ]"
    ,"place :: Int -> [[Int]]"
    ,"place s = go (abs s + 1103515245) [] [4,3,2] where"
    ," go _ acc [] = reverse acc"
    ," go x acc (n:ns) = let ps=placements n; k=x `mod` length ps; (m,cs)=ps!!k; used=mask (concat acc); x'=x*1664525+1013904223"
    ,"                    in if m .&. used == 0 then go x' (cs:acc) ns else go x' acc (n:ns)"
    ,"choose :: [Shot] -> Int"
    ,"choose ss = let sunkM=mask (concatMap sunk ss); missM=mask [cell q|q<-ss,result q==\"miss\"]; hitM=mask [cell q|q<-ss,result q==\"hit\"] .&. complement sunkM"
    ,"                 done=mask [cell q|q<-ss]; lens=[n|n<-[4,3,2], not (any (\\q -> length (sunk q)==n) ss)]"
    ,"                 ps n=[(m,cs)| (m,cs)<-placements n,m .&. missM==0,m .&. sunkM==0]"
    ,"                 worlds = case lens of"
    ,"                   [a,b,c] -> [(x,y,z)|x<-ps a,y<-ps b,z<-ps c, let u=fst x .|. fst y .|. fst z, fst x .&. fst y==0,fst x .&. fst z==0,fst y .&. fst z==0,u .&. hitM==hitM]"
    ,"                   [a,b] -> [(x,y,(0,[]))|x<-ps a,y<-ps b, let u=fst x .|. fst y, fst x .&. fst y==0,u .&. hitM==hitM]"
    ,"                   [a] -> [(x,(0,[]),(0,[]))|x<-ps a, fst x .&. hitM==hitM]"
    ,"                   _ -> []"
    ,"                 scores=foldl' (\\v (x,y,z)-> foldl' (\\w i->if testBit (fst x .|.fst y .|.fst z) i then V.modify (\\mv-> do a<-V.read mv i; V.write mv i (a+1)) w else w) v [0..63]) (V.replicate 64 (0::Int)) worlds"
    ,"                 avail=[i|i<-[0..63],not(testBit done i)]"
    ,"             in if null worlds then head avail else foldl' (\\a i->if scores V.! i > scores V.! a then i else a) (head avail) avail"
    ,"main :: IO ()"
    ,"main = do hSetBuffering stdout NoBuffering; B.getContents >>= mapM_ go . B.lines where"
    ," go l = case eitherDecode l of Right r | phase r==\"place\" -> B.putStrLn (encode (object [\"ships\" .= place (seed r `xor` roundN r)])); Right r | phase r==\"shoot\" -> B.putStrLn (encode (object [\"shot\" .= choose (shots r)])); _ -> B.putStrLn (encode (object []))"]
  copyFile "Player_v1.hs" "Player.hs"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 2000 (o++e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  s <- readFile "Player.hs"
  let s1 = filter (/= "import qualified Data.Vector as V") (lines s)
      s2 = concatMap (\x -> if "scores=foldl'" `M.isInfixOf` x
        then ["                 scores=[length [()|(x,y,z)<-worlds,testBit (fst x .|.fst y .|.fst z) i]|i<-[0..63]]"]
        else if "in if null worlds then head avail else foldl'" `M.isInfixOf` x
        then ["             in if null worlds then head avail else foldl' (\\a i->if scores!!i > scores!!a then i else a) (head avail) avail"]
        else [x]) s1
  writeFile "Player.hs" (unlines s2)
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 3000 (o++e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import Data.List (isInfixOf)

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  s <- readFile "Player.hs"
  let s1 = filter (/= "import qualified Data.Vector as V") (lines s)
      s2 = concatMap (\x -> if "scores=foldl'" `isInfixOf` x
        then ["                 scores=[length [()|(x,y,z)<-worlds,testBit (fst x .|.fst y .|.fst z) i]|i<-[0..63]]"]
        else if "in if null worlds then head avail else foldl'" `isInfixOf` x
        then ["             in if null worlds then head avail else foldl' (\\a i->if scores!!i > scores!!a then i else a) (head avail) avail"]
        else [x]) s1
  writeFile "Player.hs" (unlines s2)
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 3000 (o++e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player"] ""
  putStrLn ("compile=" ++ show ec ++ "\n" ++ take 4000 (o++e))
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","printf '%s\\n%s\\n' '{\"phase\":\"place\",\"seed\":123,\"round\":1}' '{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]}]}' | ./player"] ""
  putStrLn ("protocol=" ++ show ec ++ " output=" ++ show (o++e))
  (ec2,o2,e2) <- readProcessWithExitCode "sh" ["-c","/usr/bin/time -f '%e' sh -c 'printf \"%s\\\\n\" \"{\\\"phase\\\":\\\"shoot\\\",\\\"seed\\\":1,\\\"round\\\":1,\\\"shots\\\":[]}\" | ./player >/dev/null'"] ""
  putStrLn ("timing=" ++ show ec2 ++ " " ++ o2 ++ e2)
  pure True
module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792363073"
  let ev = object
        [ "strategy" .= ("Exact posterior occupancy over all legal non-overlapping remaining fleet placements; excludes misses and sunk cells, requires unsunk hits, chooses maximum occupancy unknown cell. Placement is deterministic seeded LCG with rejection for legal non-overlap." :: String)
        , "reusableImprovementTools" .= ("protocol shell check and cold empty-board timing command" :: String)
        , "baseline" .= object ["version" .= ("Player_v1.hs"::String), "measurements" .= ("not compiled as submitted; candidate replaced its vector scoring implementation"::String)]
        , "candidate" .= object ["version" .= ("Player.hs"::String), "measurements" .= ("compiled with prescribed Stack command; protocol check/timing recorded in console"::String)]
        ]
  BL.writeFile "evidence.json" (encode ev)
  BL.writeFile "ready.json" (encode (object ["ready" .= True]))
  xs <- mapM doesFileExist ["Player.hs","Player_v1.hs","player","evidence.json","ready.json"]
  putStrLn ("artifacts=" ++ show xs)
  pure False
module Step where
import Data.IORef
import qualified Data.Map.Strict as M

step :: IORef (M.Map String String)
     -> IORef (M.Map String (IO ()))
     -> IO Bool
step _ _ = pure False