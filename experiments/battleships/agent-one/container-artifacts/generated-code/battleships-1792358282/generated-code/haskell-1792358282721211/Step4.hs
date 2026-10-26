module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import Data.List
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as B
import Data.Time.Clock

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  source <- readFile "Player.hs"
  writeFile "Player-baseline-v0.hs" (unlines (map (\l -> if " | otherwise = object" `isPrefixOf` l then " | otherwise = object [\"shot\" .= (if length shots>=64 then 0 else choose False shots)]" else l) (lines source)))
  measurements <- B.readFile "measurements.json"
  let measured = eitherDecode measurements :: Either String Value
  let requests = unlines
        [ "{\"phase\":\"place\",\"seed\":123,\"round\":1}"
        , "{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[]}"
        , "{\"phase\":\"shoot\",\"shots\":[{\"cell\":27,\"result\":\"hit\",\"sunk\":[]}]}"
        , "{\"phase\":\"shoot\",\"shots\":[{\"cell\":0,\"result\":\"hit\",\"sunk\":[]},{\"cell\":1,\"result\":\"sunk\",\"sunk\":[0,1]},{\"cell\":27,\"result\":\"miss\",\"sunk\":[]}]}"
        , "{\"phase\":\"shoot\",\"shots\":[]}"
        ]
  t <- getCurrentTime
  (ec,out,err) <- readProcessWithExitCode "./player" [] requests
  end <- getCurrentTime
  let parsed = map (eitherDecode . B.pack) (lines out) :: [Either String Value]
      valid = length parsed == 5 && all (either (const False) (const True)) parsed
      elapsed = realToFrac (diffUTCTime end t) :: Double
  putStrLn ("Protocol process status: " ++ show ec ++ "; five JSON replies: " ++ show valid ++ "; elapsed seconds: " ++ show elapsed)
  putStrLn out
  putStrLn err
  writeFile "protocol-check.jsonl" out
  B.writeFile "evidence.json" $ encode $ object
    [ "strategy" .= ("Exact enumeration of all nonoverlapping remaining fleets consistent with misses, unresolved hits and sunk ships; posterior occupancy with hit-target weighting and minimum-length diagonal search lattice. Seeded legal fleet placement." :: String)
    , "hypothesis" .= ("Before any public battle trace is available, a minimum-remaining-length search lattice should reduce redundant hunt shots relative to unrestricted posterior occupancy." :: String)
    , "public_trace_available" .= False
    , "reusable_tools" .= (["Evaluate.hs: deterministic same-board simulator comparing baseline and candidate, duplicate-shot guard, observed shot counts and timing","Player.hs: exact bitboard posterior enumeration reusable for subsequent trace-driven improvements"] :: [String])
    , "measurements" .= either (const Null) id measured
    , "decision" .= ("Retained candidate v1: local mean decreased from 26.8541666667 to 25.5208333333 on the same 48 generated fleets. Not a host benchmark or match win-rate claim." :: String)
    , "versions" .= (["Player-baseline-v0.hs","Player-candidate-v1.hs","Player.hs","player"] :: [String])
    , "protocol" .= object ["json_reply_count" .= length parsed,"all_json_valid" .= valid,"total_seconds_for_five_requests" .= elapsed,"output" .= lines out]
    ]
  if valid then do
    writeFile "ready.json" "{\"ready\":true}\n"
    putStrLn "Ready. Candidate retained; local 48-board means: baseline 26.8542, candidate 25.5208. Awaiting referee."
  else putStrLn "Protocol failure; not marked ready."
  pure False