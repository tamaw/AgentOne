module Main where
import Text.Printf
import System.Directory
import Control.Monad
split :: String -> [String]
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  let base = "/shared/competition/paper_33935e6cb45b_m1/round-0"
      out = base ++ "/agent-one/"
  txt <- readFile (base ++ "/bars.csv")
  let rows = map split (filter (not . null) (tail (lines txt)))
      prices = map (read . (!!1)) rows :: [Double]
      n = length prices
      p = last prices
      rate k = log (p / (prices !! (n-1-k))) / fromIntegral k
      forecast = 6 * (0.50 * rate 7 + 0.35 * rate 14 + 0.15 * rate 28)
      threshold = 0.0065 :: Double
      quantity = 900 / (p * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if forecast > threshold then printf "buy,%.10f\n" quantity else ""
      manifest = "{\"code_ref\":\"/workspace/paper_33935e6cb45b_m1_agent_one_v1.hs\",\"approach\":\"Public-close-only weighted 7/14/28-bar log momentum projected over six fill-to-mark intervals; buy only above a 0.65 percent cost-and-uncertainty hurdle, otherwise retain cash. Current signal is negative, so submit header-only hold.\",\"changes\":\"Original agent-one v1; parent: none; effective round: 0. Authored offline for this task using only supplied public bars and brief. No prior improvements or own handoff were requested by this brief; no peer tips consumed. No exploratory performance claim or independent verification. Preserved executable Haskell source.\"}\n"
  forM_ ["orders.csv","manifest.json"] $ \f -> do
    exists <- doesPathExist (out ++ f)
    when exists (ioError (userError ("Refusing to overwrite existing submission: " ++ f)))
  createDirectoryIfMissing True out
  writeFile (out ++ "orders.csv") orders
  writeFile (out ++ "manifest.json") manifest
  printf "Public momentum: 7=%.6f 14=%.6f 28=%.6f; six-interval forecast=%.6f; threshold=%.6f\n" (7*rate 7) (14*rate 14) (28*rate 28) forecast threshold
  actual <- readFile (out ++ "orders.csv")
  unless (actual == orders) (ioError (userError "Orders readback mismatch"))
  actualManifest <- readFile (out ++ "manifest.json")
  unless (actualManifest == manifest) (ioError (userError "Manifest readback mismatch"))
  putStrLn "Submission readback verified:"
  putStr actual
  putStr actualManifest
