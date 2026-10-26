module Main where
import System.Directory
main :: IO ()
main = do
  let dir = "/shared/competition/match_811fe8175c96/round-0/agent-two"
  createDirectoryIfMissing True dir
  writeFile (dir ++ "/orders.csv") "side,quantity\n"
  writeFile (dir ++ "/manifest.json") "{\"code_ref\":\"/workspace/competition-agent-two-r0.hs\",\"approach\":\"Independent cost-aware dual-horizon momentum: require positive 7-bar and 21-bar returns before initiating a long. Current 7-bar return +8.1433%, 21-bar return -3.4806%; retain 100% cash. No leverage or fill-price feasibility risk on this hold.\",\"changes\":\"Initial strategy. Considered a faster rebound-only entry, but rejected it: six overlapping historical rebound signals averaged -3.064% after estimated round-trip costs; this tiny dependent sample is not proof. Recent rebound has slowed and does not yet overcome the broader decline. No peer submissions inspected; no strategy coordination.\"}\n"
  a <- readFile (dir ++ "/orders.csv")
  b <- readFile (dir ++ "/manifest.json")
  if a == "side,quantity\n" && b == "{\"code_ref\":\"/workspace/competition-agent-two-r0.hs\",\"approach\":\"Independent cost-aware dual-horizon momentum: require positive 7-bar and 21-bar returns before initiating a long. Current 7-bar return +8.1433%, 21-bar return -3.4806%; retain 100% cash. No leverage or fill-price feasibility risk on this hold.\",\"changes\":\"Initial strategy. Considered a faster rebound-only entry, but rejected it: six overlapping historical rebound signals averaged -3.064% after estimated round-trip costs; this tiny dependent sample is not proof. Recent rebound has slowed and does not yet overcome the broader decline. No peer submissions inspected; no strategy coordination.\"}\n"
    then putStrLn "Round 0 submission readback verified: deliberate cash hold."
    else ioError (userError "Submission readback mismatch")
