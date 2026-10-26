module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import System.Exit
import Data.Char
import Data.List
import Text.Read

renameChoose :: String -> String
renameChoose []=[]
renameChoose s@(c:cs)
 | isAlpha c || c=='_' = let (a,b)=span (\x->isAlphaNum x || x=='_') s in (if a=="choose" then "chooseOriginal" else a)++renameChoose b
 | otherwise=c:renameChoose cs

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
 setCurrentDirectory "/workspace/.runs/battleships-1792358282"
 createDirectoryIfMissing True "versions/game3"
 mapM_ (\f->copyFile f ("versions/game3/"++f)) ["Fleet.hs","Player.hs","player","evidence.json","feedback.json"]
 old<-readFile "Fleet.hs"
 writeFile "FleetOld.hs" (unlines [if l=="module Fleet where" then "module FleetOld where" else l | l<-lines old])
 let new=unlines
       ["choose seed round ss = chooseBonus 2 seed round ss",
        "chooseBonus bonus seed round ss",
        " | unresolved==0 = chooseOriginal seed round ss",
        " | maximum (elems scores)==0 = chooseOriginal seed round ss",
        " | otherwise = maximumBy (\\a b -> compare (scores!a,a==preferred,negate a) (scores!b,b==preferred,negate b)) untried",
        " where",
        " preferred=chooseOriginal seed round ss",
        " tried=mask [c | (c,_,_)<-ss]",
        " sunkCells=concat [cs | (_,r,cs)<-ss,r==\"sunk\"]",
        " blocked=mask ([c | (c,r,_)<-ss,r==\"miss\"]++sunkCells)",
        " unresolved=mask [c | (c,r,_)<-ss,r/=\"miss\",c `notElem` sunkCells]",
        " remaining=foldl' (flip delete) [4,3,2] [length cs | (_,r,cs)<-ss,r==\"sunk\"]",
        " untried=[c | c<-[0..63],not(testBit tried c)]",
        " options=[[ (m,filter (not . testBit tried) cs) | (m,cs)<-placements n,m .&. blocked==0,m .&. complement tried/=0] | n<-remaining]",
        " scores :: UArray Int Int",
        " scores=runSTUArray $ do",
        "  ar<-newArray (0,63) 0",
        "  let visit used ships [] = when (used .&. unresolved==unresolved) $ forM_ ships $ \\cs ->",
        "        forM_ cs $ \\c -> do",
        "          v<-readArray ar c",
        "          writeArray ar c (v+4+if length cs==1 then bonus else 0)",
        "      visit used ships (ps:rest) = forM_ ps $ \\(m,cs) -> when (used .&. m==0) (visit (used .|. m) (cs:ships) rest)",
        "  visit 0 [] options",
        "  return ar"]
 let proposed=renameChoose old++"\n"++new
 writeFile "Fleet.hs" proposed
 ev<-readFile "Compare.hs"
 let prefix=takeWhile (/="main=do") (lines ev)
 writeFile "PursuitCompare.hs" $ unlines $ prefix++
    ["main=do",
     " t0<-getCPUTime",
     " let seeds=[93001..93024]; bs=map (simulate (\\s->O.choose s 1)) seeds; cs=map (simulate (\\s->choose s 1)) seeds",
     " evaluate (sum bs+sum cs)",
     " t1<-getCPUTime",
     " print (bs,cs,fromIntegral(t1-t0)/1e12::Double)"]
 (c,o,e)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","PursuitCompare.hs","-o","pursuit-compare"] ""
 putStrLn o
 putStrLn e
 (bc,bo,be)<-if c==ExitSuccess then readProcessWithExitCode "timeout" ["36","./pursuit-compare"] "" else pure(c,"",e)
 putStrLn ("Observed paired pursuit benchmark: "++show bc++" "++bo++be)
 let measured=if bc==ExitSuccess then readMaybe bo :: Maybe ([Int],[Int],Double) else Nothing
     adopt=case measured of Just(bs,cs,_) -> sum cs<sum bs; _->False
 writeFile "versions/game3/CandidateFleet.hs" proposed
 if adopt then pure () else writeFile "Fleet.hs" old
 (pc,po,pe)<-readProcessWithExitCode "stack" ["--stack-yaml","/workspace/stack.yaml","--allow-different-user","exec","--","ghc","-O2","-package","aeson","Player.hs","-o","player"] ""
 putStrLn po
 putStrLn pe
 (qc,qo,qe)<-readProcessWithExitCode "./player" [] (unlines ["{\"phase\":\"place\",\"seed\":123,\"round\":4}","{\"phase\":\"shoot\",\"seed\":123,\"round\":4,\"shots\":[]}","{\"phase\":\"shoot\",\"seed\":123,\"round\":4,\"shots\":[{\"cell\":0,\"result\":\"hit\",\"sunk\":[]}]}"])
 putStrLn ("Observed protocol: "++show qc++"\n"++qo++qe)
 writeFile "versions/game3/protocol.txt" qo
 let stats=case measured of
       Nothing -> "\"measurement_status\":\"candidate evaluation unavailable; incumbent retained\""
       Just(bs,cs,t) -> "\"measurement_status\":\"actual local paired simulations; not host benchmark or match win rates\",\"seeds_start\":93001,\"baseline_shots\":"++show bs++",\"candidate_shots\":"++show cs++",\"baseline_mean\":"++show(fromIntegral(sum bs)/24::Double)++",\"candidate_mean\":"++show(fromIntegral(sum cs)/24::Double)++",\"cpu_seconds\":"++show t
 writeFile "evidence.json" $ "{\"public_feedback\":\"Game 3 public trace and own fleet preserved in versions/game3/feedback.json; no opponent fleet inspected\",\"weakness\":\"Occupancy-only shot utility does not explicitly reward completing a ship, and posterior enumeration should exclude remaining ships that would already have sunk.\",\"hypothesis\":\"During unresolved-hit pursuit, exact consistent fleets with a 50 percent completion bonus can reduce finishing delay; hunt phase unchanged.\",\"candidate_change\":\"Exact residual-fleet pursuit with already-sunk-consistency filtering and completion-weighted marginals\",\"reusable_helper\":\"PursuitCompare.hs paired evaluator; chooseBonus reusable tunable pursuit function, preserved in versions/game3/CandidateFleet.hs\",\"adopted_locally\":"++(if adopt then "true" else "false")++","++stats++"}\n"
 if pc==ExitSuccess && qc==ExitSuccess && length(lines qo)==3 then writeFile "ready.json" "{\"ready\":true}\n" >> putStrLn ("Ready; candidate adopted: "++show adopt) else putStrLn "Not ready."
 pure False