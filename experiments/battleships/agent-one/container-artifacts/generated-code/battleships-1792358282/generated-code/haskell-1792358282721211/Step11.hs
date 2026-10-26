module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process
import Data.List
import Control.Monad

replace :: String -> String -> String -> String
replace a b s
  | null s = []
  | a `isPrefixOf` s = b ++ replace a b (drop (length a) s)
  | otherwise = head s : replace a b (tail s)

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  src <- readFile "Player.hs"
  length src `seq` copyFile "Player.hs" "Player-before-game3.hs"
  copyFile "player" "player-before-game3"
  copyFile "evidence.json" "evidence-game2.json"
  writeFile "Incumbent.hs" (replace "module Main where" "module Incumbent where" src)
  let candidate=replace "then 1.0 else 0.85" "then 1.0 else 0.20" src
  writeFile "Player.hs" candidate
  writeFile "Player-candidate-v3.hs" candidate
  tool <- readFile "Compare.hs"
  length tool `seq` writeFile "Compare-game2.hs" tool
  writeFile "Compare.hs" (replace "game2" "game3" tool)
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player > build-game3.log 2>&1 && stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson -main-is Compare Compare.hs Player.hs Incumbent.hs -o compare >>build-game3.log 2>&1 && ./compare > comparison-game3.log; cat build-game3.log; tail -3 comparison-game3.log; cat comparison-game3.json"] ""
  print ec
  putStrLn o
  putStrLn e
  ok <- doesFileExist "comparison-game3.json"
  unless ok $ do
    copyFile "Player-before-game3.hs" "Player.hs"
    copyFile "player-before-game3" "player"
  (pec,po,pe) <- readProcessWithExitCode "./player" [] (unlines
    ["{\"phase\":\"place\",\"seed\":123,\"round\":4}"
    ,"{\"phase\":\"shoot\",\"shots\":[]}"
    ,"{\"phase\":\"shoot\",\"shots\":[{\"cell\":22,\"result\":\"hit\",\"sunk\":[]},{\"cell\":30,\"result\":\"miss\",\"sunk\":[]},{\"cell\":21,\"result\":\"miss\",\"sunk\":[]},{\"cell\":14,\"result\":\"hit\",\"sunk\":[]}]}"
    ])
  putStrLn ("Observed protocol status "++show pec++"; replies="++show (length(lines po)))
  putStrLn po
  putStrLn pe
  writeFile "protocol-game3.jsonl" po
  measure <- if ok then readFile "comparison-game3.json" else pure "null"
  writeFile "evidence.json" $ "{\"phase\":\"after game 3\",\"trace_observation\":\"Round 3 lost. Public trace includes unresolved hits 22 and 14 after misses at 30 and 21.\",\"weakness\":\"Current posterior scoring only mildly favors placements intersecting unresolved hits: factor 1 versus 0.85. This can divert shots to unrelated ships before finishing known damage.\",\"hypothesis\":\"Reducing unrelated-placement weight to 0.20 while unresolved hits exist should improve target completion and reduce ambiguity from touching ships. This is a heuristic, not an established optimal policy.\",\"change_applied_to_source\":"++(if src/=candidate then "true" else "false")++",\"measured\":"++measure++",\"selection\":\"Candidate retained only if its local same-board mean does not regress; otherwise source and executable restored automatically.\",\"reusable_helper\":\"Compare.hs uses identical deterministic fleets, validates range and duplicate shots, reports policy means and automatically rolls back regressions. Prior comparison source preserved as Compare-game2.hs.\",\"artifacts\":[\"Player-before-game3.hs\",\"player-before-game3\",\"Player-candidate-v3.hs\",\"comparison-game3.log\",\"protocol-game3.jsonl\",\"evidence-game2.json\"],\"limitations\":\"48 local generated fleets only; not hidden training fleets or match win rate. No opponent fleet inspected.\"}\n"
  writeFile "ready.json" "{\"ready\":true}\n"
  putStrLn "Ready; local measured selection completed, incumbent preserved on regression."
  pure False