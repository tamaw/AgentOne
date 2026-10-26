module Main where
import System.Directory
main :: IO ()
main = do
  let target = "/shared/competition/pt-v3-dryrun-0ecd98594047/round-1/agent-one"
  createDirectoryIfMissing True target
  writeFile (target ++ "/orders.csv") "side,quantity\nbuy,4.0\n"
  writeFile (target ++ "/manifest.json") "{\"code_ref\":\"/workspace/pt-v3-dryrun-0ecd98594047-round-1.hs\",\"approach\":\"Partial contrarian long after the recent drawdown within a positive full-history trend. Buy four index units and retain the remaining cash. Future fill prices and returns are unknown.\",\"changes\":\"Replace the previous cash-only position with a partial long for the final round; reserve substantial cash for next-close execution uncertainty.\"}\n"
