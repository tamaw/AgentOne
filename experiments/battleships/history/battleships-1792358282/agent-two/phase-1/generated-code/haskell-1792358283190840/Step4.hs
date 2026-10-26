module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import System.Exit

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  createDirectoryIfMissing True "versions/initial"
  mapM_ (\f -> copyFile f ("versions/initial/"++f)) ["Player.hs","Fleet.hs","player"]
  writeFile "Evaluate.hs" $ unlines
    [ "{-# LANGUAGE BangPatterns #-}"
    , "module Main where"
    , "import Fleet"
    , "import Data.List"
    , "import System.CPUTime"
    , "import Control.Exception"
    , "simulate :: (Int -> [Shot] -> Int) -> Int -> Int"
    , "simulate policy seed=go [] where"
    , " ships=fleet seed 17"
    , " allCells=concat ships"
    , " go ss | all (`elem` map (\\(c,_,_)->c) ss) allCells = length ss"
    , "       | otherwise = let c=policy seed ss; fired=c:map (\\(x,_,_)->x) ss; target=find (elem c) ships; (r,sk)=case target of Nothing -> (\"miss\",[]); Just cs -> if all (`elem` fired) cs then (\"sunk\",cs) else (\"hit\",[]) in if c `elem` tail fired then error \"repeated shot\" else go (ss++[(c,r,sk)])"
    , "baseline seed ss = head [c | c<-sortOn (\\x->mix (fromIntegral seed+fromIntegral x*123456789)) [0..63],c `notElem` [a|(a,_,_)<-ss]]"
    , "main=do"
    , " t0<-getCPUTime"
    , " let seeds=[91001..91008]; bs=map (simulate baseline) seeds; cs=map (simulate (\\s->choose s 1)) seeds"
    , " evaluate (sum bs+sum cs)"
    , " t1<-getCPUTime"
    , " let mean xs=fromIntegral(sum xs)/fromIntegral(length xs)::Double"
    , " putStrLn $ \"{\\\"strategy\\\":\\\"Exact uniform posterior over all legal remaining nonoverlapping fleets, constrained by misses, unresolved hits and sunk ships; shoot maximum posterior occupancy. Seeded legal placement.\\\",\\\"reusable_tool\\\":\\\"Fleet.hs exact bitmask posterior and Evaluate.hs deterministic full-game simulator\\\",\\\"hypothesis\\\":\\\"Fleet-consistent posterior occupancy clears boards faster than seeded random untried-cell baseline\\\",\\\"measurement_scope\\\":\\\"8 locally generated deterministic fleets, not host hidden training fleets; CPU seconds cover both policies\\\",\\\"seeds\\\":\"++show seeds++\",\\\"baseline_shots\\\":\"++show bs++\",\\\"candidate_shots\\\":\"++show cs++\",\\\"baseline_mean\\\":\"++show(mean bs)++\",\\\"candidate_mean\\\":\"++show(mean cs)++\",\\\"cpu_seconds\\\":\"++show(fromIntegral(t1-t0)/1e12::Double)++\",\\\"protocol_checks\\\":\\\"persistent process: placement, empty history, miss and sunk history requests; measured separately in protocol-check.txt\\\",\\\"version\\\":\\\"versions/initial\\\"}\""
    ]
  (bc,bo,be) <- readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","Evaluate.hs","-o","evaluate"] ""
  putStrLn bo
  putStrLn be
  let inputs=unlines ["{\"phase\":\"place\",\"seed\":123,\"round\":1}","{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[]}","{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]}]}","{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[{\"cell\":0,\"result\":\"hit\",\"sunk\":[]},{\"cell\":1,\"result\":\"sunk\",\"sunk\":[0,1]}]}"]
  (pc,po,pe) <- readProcessWithExitCode "/usr/bin/time" ["-f","elapsed_seconds=%e","./player"] inputs
  writeFile "protocol-check.txt" (po++pe)
  putStrLn ("Observed persistent JSON-lines protocol: "++show pc)
  putStrLn po
  putStrLn pe
  if bc==ExitSuccess then do
    (ec,o,e)<-readProcessWithExitCode "timeout" ["42","./evaluate"] ""
    putStrLn ("Benchmark: "++show ec)
    putStrLn o
    putStrLn e
    if ec==ExitSuccess then writeFile "evidence.json" o else writeFile "evidence.json" "{\"strategy\":\"Exact fleet posterior occupancy\",\"reusable_tool\":\"Fleet.hs and Evaluate.hs\",\"measurement\":\"Local benchmark timed out; protocol checks recorded in protocol-check.txt\",\"baseline\":null,\"candidate\":null}"
  else writeFile "evidence.json" "{\"strategy\":\"Exact fleet posterior occupancy\",\"measurement\":\"Protocol checks recorded in protocol-check.txt; benchmark compilation failed\",\"baseline\":null,\"candidate\":null}"
  if pc==ExitSuccess && length(lines po)==4 then do
    writeFile "ready.json" "{\"ready\":true}\n"
    putStrLn "Player compiled and checked; ready.json written."
  else putStrLn "Protocol failed; not marked ready."
  pure False