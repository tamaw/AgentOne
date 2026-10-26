module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import System.Exit
import Data.List
import Text.Read

replace :: String -> String -> String -> String
replace a b s | a `isPrefixOf` s = b ++ drop (length a) s
replace a b (x:xs) = x:replace a b xs
replace _ _ [] = []

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
 setCurrentDirectory "/workspace/.runs/battleships-1792358282"
 feedback <- readFile "feedback.json"
 putStrLn feedback
 createDirectoryIfMissing True "versions/game1"
 mapM_ (\f -> copyFile f ("versions/game1/"++f)) ["Fleet.hs","Player.hs","player"]
 old <- readFile "Fleet.hs"
 writeFile "FleetOld.hs" (replace "module Fleet where" "module FleetOld where" old)
 let candidate=replace " available=[c | c<-[0..63],not(testBit tried c)]"
       (unlines [" allAvailable=[c | c<-[0..63],not(testBit tried c)]",
                 " modulus=if null lens then 2 else minimum lens",
                 " residue=abs (seed `mod` modulus)",
                 " lattice=[c | c<-allAvailable,(c `div` 8+c `mod` 8) `mod` modulus==residue,counts!c>0]",
                 " available=if hits==0 && not(null lattice) then lattice else allAvailable"]) old
 writeFile "Fleet.hs" candidate
 ev <- readFile "Evaluate.hs"
 let prefix=takeWhile (/="main=do") (lines ev)
 writeFile "Compare.hs" $ unlines $
   map (replace "import Fleet" "import Fleet\nimport qualified FleetOld as O") prefix ++
   ["main=do",
    " t0<-getCPUTime",
    " let seeds=[91001..91008]; bs=map (simulate (\\s->O.choose s 1)) seeds; cs=map (simulate (\\s->choose s 1)) seeds",
    " evaluate (sum bs+sum cs)",
    " t1<-getCPUTime",
    " print (bs,cs,fromIntegral(t1-t0)/1e12::Double)"]
 (cc,co,ce)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","Compare.hs","-o","compare"] ""
 putStrLn co
 putStrLn ce
 (bc,bo,be)<-if cc==ExitSuccess then readProcessWithExitCode "timeout" ["38","./compare"] "" else pure (cc,"",ce)
 putStrLn ("Observed paired benchmark: "++show bc++" "++bo++be)
 let measured=if bc==ExitSuccess then readMaybe bo :: Maybe ([Int],[Int],Double) else Nothing
 let adopt=case measured of Just (bs,cs,_) -> sum cs <= sum bs; Nothing -> False
 if adopt then pure () else writeFile "Fleet.hs" old
 copyFile "Compare.hs" "versions/game1/Compare.hs"
 writeFile "versions/game1/CandidateFleet.hs" candidate
 (pc,po,pe)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","Player.hs","-o","player"] ""
 putStrLn po
 putStrLn pe
 (qc,qo,qe)<-readProcessWithExitCode "./player" [] (unlines ["{\"phase\":\"place\",\"seed\":123,\"round\":2}","{\"phase\":\"shoot\",\"seed\":123,\"round\":2,\"shots\":[]}","{\"phase\":\"shoot\",\"seed\":123,\"round\":2,\"shots\":[{\"cell\":0,\"result\":\"hit\",\"sunk\":[]}]}"])
 putStrLn ("Real persistent protocol check: "++show qc)
 putStrLn qo
 putStrLn qe
 writeFile "protocol-check.txt" qo
 let measurements=case measured of
       Nothing -> "\"measurement_status\":\"paired benchmark unavailable or timed out; incumbent retained\",\"baseline_mean\":null,\"candidate_mean\":null"
       Just (bs,cs,t) -> "\"measurement_status\":\"observed local paired simulation; not host hidden fleets\",\"seeds\":[91001,91002,91003,91004,91005,91006,91007,91008],\"baseline_shots\":"++show bs++",\"candidate_shots\":"++show cs++",\"baseline_mean\":"++show (fromIntegral(sum bs)/8::Double)++",\"candidate_mean\":"++show (fromIntegral(sum cs)/8::Double)++",\"cpu_seconds\":"++show t
 writeFile "evidence.json" $ "{\"weakness\":\"Original greedy posterior occupancy has no hunt-phase covering constraint; it can spend hunt shots on both parities while a length-2 ship remains.\",\"hypothesis\":\"Restrict hit-free hunting to a diagonal residue modulo shortest remaining ship length; every possible remaining ship intersects that lattice. Keep exact posterior and unrestricted hit pursuit.\",\"public_feedback\":\"Game 1 lost; feedback.json retained, no enemy fleet inspected.\",\"reusable_helpers\":\"Fleet.hs bitmask posterior, FleetOld.hs saved baseline, Compare.hs paired deterministic full-game simulator\",\"candidate_preserved\":\"versions/game1/CandidateFleet.hs\",\"adopted_locally\":"++(if adopt then "true" else "false")++","++measurements++",\"protocol_output_lines\":"++show(length(lines qo))++"}\n"
 if pc==ExitSuccess && qc==ExitSuccess && length(lines qo)==3 then do
   writeFile "ready.json" "{\"ready\":true}\n"
   putStrLn ("Ready. Lattice candidate adopted locally: "++show adopt)
 else putStrLn "Compilation or protocol failure."
 pure False