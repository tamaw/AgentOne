module Main where
import System.Directory
import Control.Monad
main :: IO ()
main = do
  let target = "/shared/competition/match_811fe8175c96/round-1/agent-one"
      orders = "side,quantity\nbuy,10\n"
      fields = [("code_ref","/workspace/match_811fe8175c96/Round1.hs"),
                ("approach","Independent public-history recovery/momentum entry. Buy 10 units: approximately 80.7% of capital including friction at the decision close. Price has reached a trailing-20-bar high with positive 5/10/20-bar momentum. Leave approximately 19.3% cash as downside exposure reduction and a next-close execution-price reserve; no leverage. Actual fill affordability depends on the unknown next close."),
                ("changes","Move from the prior settled cash-only position to a partial long recovery position. Recent eligible forward outcomes improved, but overlapping samples are weak evidence, older short-momentum outcomes were negative, and 30-bar momentum remains negative. These conflicting signals argue against full deployment; no peer submission was inspected and no peer coordination used.")]
      manifest = "{" ++ joinFields fields ++ "}\n"
  createDirectoryIfMissing True target
  writeFile (target ++ "/orders.csv") orders
  writeFile (target ++ "/manifest.json") manifest
  o <- readFile (target ++ "/orders.csv")
  m <- readFile (target ++ "/manifest.json")
  unless (o == orders && m == manifest && lines o == ["side,quantity","buy,10"] && all (not . null . snd) fields) (ioError (userError "Submission readback or format validation failed"))
  putStrLn "Round 1 orders and required manifest written and exact readback verified: buy 10 units. Settlement/acceptance is not yet verified."
  putStrLn "Decision-close estimated all-in cost: 806.68; cash reserve: 193.32. Order fits 1000 cash only if next close is at most approximately 99.8502; the future close is unknown. Typical daily volatility was approximately 1.85%; the reserve is not a guarantee against rejection."
joinFields :: [(String,String)] -> String
joinFields [] = ""
joinFields [(k,v)] = show k ++ ":" ++ show v
joinFields ((k,v):xs) = show k ++ ":" ++ show v ++ "," ++ joinFields xs
