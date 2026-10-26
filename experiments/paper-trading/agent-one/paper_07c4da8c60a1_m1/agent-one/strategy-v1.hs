#!/usr/bin/env runghc
module Main where
import System.Directory
import Control.Monad
import Text.Printf

split :: String -> [String]
split s = case break (==',') s of
  (a,[]) -> [a]
  (a,_:b) -> a:split b

fit :: [Double] -> (Double,Double,Double)
fit xs = (a,b,sd)
  where
    pairs = zip xs (tail xs)
    n = fromIntegral (length pairs)
    mx = sum (map fst pairs)/n
    my = sum (map snd pairs)/n
    b = sum [(x-mx)*(y-my) | (x,y) <- pairs] / sum [(x-mx)^2 | (x,_) <- pairs]
    a = my-b*mx
    sd = sqrt (sum [(y-a-b*x)^2 | (x,y) <- pairs]/(n-2))

main :: IO ()
main = do
  let base = "/shared/competition/paper_07c4da8c60a1_m1/round-0"
      target = base ++ "/agent-one"
      codeRef = "/workspace/paper_07c4da8c60a1_m1/agent-one/strategy-v1.hs"
  csv <- readFile (base ++ "/bars.csv")
  let rows = map split (drop 1 (lines csv))
  unless (length rows == 60 && all ((==3) . length) rows) (fail "Unexpected public input")
  let prices = [read (row!!1) :: Double | row <- rows]
      p = last prices
      models = [fit (drop start prices) | start <- [7,15,20,30]]
      predictions = [(a+b*p, iterate (\x -> a+b*x) p !! 7,sd) | (a,b,sd) <- models]
      edge = sum [mark/entry-1 | (entry,mark,_) <- predictions]/4
      ceilingPrice = maximum [entry+6*sd | (entry,_,sd) <- predictions]
      q = fromIntegral (floor (1000/(ceilingPrice*1.0005*1.001)*1000000) :: Integer)/1000000 :: Double
      orderText = if edge > 0.0015 && q > 0 then printf "side,quantity\nbuy,%.6f\n" q else "side,quantity\n"
      approach = "PAPER ONLY. Public-close AR(1) mean reversion ensemble fitted from t=7,15,20,30 through t=59. Buy only when mean predicted next-close to seven-bar-mark return exceeds 0.15 percent. Size from cash 1000 using maximum model next-close forecast plus six residual standard deviations and exact buy fee/slippage factors, rounded down to six decimal units. This reserve is a statistical buffer, not a guaranteed bound on the unknown next close. No leverage or shorting. Volume is public but unused."
      changes = "Initial original agent-one implementation, version v1, parent none, effective round 0. Own public-only exploratory AR fits indicated positive next-fill-to-mark mean-reversion returns across all four windows; selected a buffered long position accordingly. Exploratory agent-reported calculations are not independent verification or settlement. No prior improvements or handoff were requested by the brief, and no peer tips or peer current submissions were accessed. No infrastructure, repository, or engine changes."
      fields = [("code_ref",codeRef),("approach",approach),("changes",changes),("version","v1"),("parent","none; original implementation"),("effective_round","0")]
      manifestText = "{\n" ++ concat ["  " ++ show k ++ ": " ++ show v ++ (if i == length fields-1 then "\n" else ",\n") | (i,(k,v)) <- zip [0..] fields] ++ "}\n"
  unless (all (not . null . snd) fields) (fail "Empty manifest field")
  createDirectoryIfMissing True target
  forM_ ["orders.csv","manifest.json"] $ \f -> do
    present <- doesPathExist (target ++ "/" ++ f)
    when present (fail ("Refusing to overwrite existing submission: " ++ f))
  writeFile (target ++ "/manifest.json") manifestText
  writeFile (target ++ "/orders.csv") orderText
  actualOrders <- readFile (target ++ "/orders.csv")
  actualManifest <- readFile (target ++ "/manifest.json")
  unless (actualOrders == orderText && actualManifest == manifestText) (fail "Submission readback mismatch")
  printf "Public-model average next-fill-to-mark forecast: %.4f%%; sizing ceiling: %.6f index units.\n" (edge*100) ceilingPrice
  putStrLn "Submission files created and exact readback checked."
  putStr actualOrders
  putStr actualManifest
