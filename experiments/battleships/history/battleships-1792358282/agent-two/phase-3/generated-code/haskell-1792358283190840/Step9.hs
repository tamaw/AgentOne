module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import System.Exit
import Data.Char
import Data.List
import Text.Read

rename :: String -> String
rename []=[]
rename s@(c:cs)
 | isAlpha c || c=='_' = let (a,b)=span (\x->isAlphaNum x || x=='_') s in (if a=="fleet" then "fleetBase" else a)++rename b
 | otherwise=c:rename cs

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
 setCurrentDirectory "/workspace/.runs/battleships-1792358282"
 createDirectoryIfMissing True "versions/game2"
 mapM_ (\f -> copyFile f ("versions/game2/"++f)) ["Fleet.hs","Player.hs","player","feedback.json","evidence.json"]
 old<-readFile "Fleet.hs"
 writeFile "FleetOld.hs" (unlines (map (\l->if "module Fleet where" `isPrefixOf` l then "module FleetOld where" else l) (lines old)))
 let extra=unlines
       ["edgeFleet n seed round = foldl1 better [fleetBase (seed+k*7919) round | k<-[0..n-1]]",
        " where",
        " score ss = sum [let r=c `div` 8; q=c `mod` 8 in (2*r-7)^2+(2*q-7)^2 | c<-concat ss]",
        " better a b = if score a>=score b then a else b",
        "fleet = edgeFleet 16"]
 let proposed=rename old++"\n"++extra
 writeFile "Fleet.hs" proposed
 ev<-readFile "Compare.hs"
 let prefix=takeWhile (/="main=do") (lines ev)
     changed=map (\l->if " ships=fleet seed 17"==l then " ships=layout seed 17" else if "simulate policy seed=go [] where"==l then "simulate layout policy seed=go [] where" else if "simulate ::" `isPrefixOf` l then "simulate :: (Int -> Int -> [[Int]]) -> (Int -> [Shot] -> Int) -> Int -> Int" else l) prefix
 writeFile "DefenseCompare.hs" $ unlines $ changed++
    ["main=do",
     " t0<-getCPUTime",
     " let seeds=[92001..92048]; baseline=map (simulate O.fleet (\\s->O.choose s 1)) seeds; candidates=[map (simulate (edgeFleet n) (\\s->O.choose s 1)) seeds | n<-[4,16,64]]",
     " evaluate (sum baseline+sum (map sum candidates))",
     " t1<-getCPUTime",
     " print (baseline,candidates,fromIntegral(t1-t0)/1e12::Double)"]
 (c,o,e)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","DefenseCompare.hs","-o","defense-compare"] ""
 putStrLn o
 putStrLn e
 (bc,bo,be)<-if c==ExitSuccess then readProcessWithExitCode "timeout" ["38","./defense-compare"] "" else pure(c,"",e)
 putStrLn ("Observed defensive benchmark: "++show bc++" "++bo++be)
 let measured=if bc==ExitSuccess then readMaybe bo :: Maybe ([Int],[[Int]],Double) else Nothing
     selected=case measured of
       Just (bs,cs,_) -> snd $ maximum [(sum bs,0)] `max` maximum [(sum xs,n) | (n,xs)<-zip [4,16,64] cs]
       Nothing -> 0
     finalSource=if selected==0 then old else rename old++"\n"++unlines (init(lines extra))++"\nfleet = edgeFleet "++show selected++"\n"
 writeFile "versions/game2/CandidateFleet.hs" proposed
 writeFile "Fleet.hs" finalSource
 (pc,po,pe)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","Player.hs","-o","player"] ""
 putStrLn po
 putStrLn pe
 (qc,qo,qe)<-readProcessWithExitCode "./player" [] (unlines ["{\"phase\":\"place\",\"seed\":123,\"round\":3}","{\"phase\":\"shoot\",\"seed\":123,\"round\":3,\"shots\":[]}","{\"phase\":\"shoot\",\"seed\":123,\"round\":3,\"shots\":[{\"cell\":0,\"result\":\"hit\",\"sunk\":[]}]}"])
 putStrLn ("Observed protocol: "++show qc++"\n"++qo++qe)
 let stats=case measured of
       Nothing -> "\"measurement_status\":\"local evaluation unavailable; original retained\""
       Just (bs,cs,t) -> "\"measurement_status\":\"actual 48 local generated fleets per placement policy; same incumbent shooter; not host hidden benchmark or match win rate\",\"seeds_start\":92001,\"baseline_shots\":"++show bs++",\"candidate_shots_4_16_64\":"++show cs++",\"baseline_mean\":"++show(fromIntegral(sum bs)/48::Double)++",\"candidate_means\":"++show[ fromIntegral(sum xs)/48::Double | xs<-cs]++",\"cpu_seconds\":"++show t
 writeFile "evidence.json" $ "{\"public_feedback\":\"Game 2 lost; public trace and own fleet saved in versions/game2/feedback.json\",\"weakness\":\"Uniform placement exposes central high-density cells to posterior-greedy hunting; previous lattice hunting regressed locally and was rejected.\",\"hypothesis\":\"Selecting edge-biased legal layouts delays posterior-greedy discovery. Touching remains legal; no hidden fleet read.\",\"change\":\"Placement only; shooting unchanged. Select most edge-biased of N seeded valid layouts.\",\"selected_N\":"++show selected++",\"reusable_helper\":\"DefenseCompare.hs paired placement-defense evaluator, edgeFleet cheap deterministic legal-fleet selector; all prior versions saved\",\"selection_caveat\":\"N chosen on local simulation; generalization to opponent is a hypothesis\","++stats++"}\n"
 if pc==ExitSuccess && qc==ExitSuccess && length(lines qo)==3 then writeFile "ready.json" "{\"ready\":true}\n" >> putStrLn "Ready; real JSON-lines protocol checked." else putStrLn "Not ready."
 pure False