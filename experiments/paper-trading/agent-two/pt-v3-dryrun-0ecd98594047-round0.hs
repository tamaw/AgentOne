module Main where
import System.Directory
main :: IO ()
main = do
  let target = "/shared/competition/pt-v3-dryrun-0ecd98594047/round-0/agent-two"
  createDirectoryIfMissing True target
  writeFile (target ++ "/orders.csv") "side,quantity\n"
  writeFile (target ++ "/manifest.json") "{\"code_ref\":\"/workspace/pt-v3-dryrun-0ecd98594047-round0.hs\",\"approach\":\"Long-only momentum filter: retain cash when the latest close is below its 20-bar simple moving average and 10-bar momentum is negative. At t=59, close=112.18087997861295, SMA20=116.01140910252566, and 10-bar return=-4.857501758482774 percent. No order; avoid fees and next-close execution uncertainty.\",\"changes\":\"Initial round submission. Preserve existing cash of 1000 and zero units; reassess on the next round using newly available public bars.\"}\n"
