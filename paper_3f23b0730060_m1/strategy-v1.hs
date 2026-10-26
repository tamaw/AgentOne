module Main where
import System.Directory
import System.Process
import Control.Monad
import Text.Read (readMaybe)
import Data.List (intercalate)
root :: FilePath
root = "/shared/competition/paper_3f23b0730060_m1/round-0"
source :: FilePath
source = "/workspace/paper_3f23b0730060_m1/strategy-v1.hs"
split :: String -> [String]
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
mean xs = sum xs / fromIntegral (length xs)
forecast ps = let xs=init ps; ys=tail ps; mx=mean xs; my=mean ys; den=sum [(x-mx)^2 | x<-xs]; raw=if den>0 then sum [(x-mx)*(y-my) | (x,y)<-zip xs ys]/den else 0; b=max 0 (min 0.995 raw); a=my-b*mx; fs=iterate (\x->a+b*x) (last ps) in (fs!!1,fs!!7,b,a/(1-b))
main :: IO ()
main = do
  csv <- readFile (root++"/bars.csv")
  let rows=map split (tail (lines csv))
  unless (length rows==60 && all ((==3).length) rows) $ fail "Unexpected public bars"
  let ps=map (read . (!!1)) rows :: [Double]
      (f1,f7,b,m)=forecast ps
      (g1,g7,c,n)=forecast (drop 30 ps)
      expectedFill=(f1+g1)/2
      expectedMark=(f7+g7)/2
      edge=expectedMark/expectedFill-1
      cost=1.0005*1.001
      q=fromIntegral (floor (0.90*1000/(last ps*cost)*1000000) :: Integer)/1000000 :: Double
      enter=edge>cost-1
      order="side,quantity\n" ++ if enter then "buy,"++show q++"\n" else ""
      out=root++"/agent-one"
  digest <- head . words <$> readProcess "sha256sum" [source] ""
  let ref="sha256:"++digest
      approach="Public-close mean-reversion ensemble: OLS AR(1) on all 60 and trailing 30 closes, slopes clipped to [0,0.995]; average forecasts at next-close fill and seven-bar mark. Buy only when forecast mark/fill return exceeds 0.15005% entry friction; otherwise hold cash. Quantity uses 90% of cash at last close including entry friction, leaving a next-close price buffer; no guarantee against arbitrary gaps. Volume unused."
      changes="Source version v1, exact hash "++ref++"; parent none (initial submission); effective round 0. Hypothesis: deviations below estimated equilibrium may revert over the six held intervals. Actual changes: initial implementation of the 60/30-close AR ensemble, friction gate, and 90% sizing; no prior strategy modified. Fitted only to supplied public history; no out-of-sample testing or improvement claim. Only routine settlement is authoritative."
      manifest="{\"code_ref\":"++show ref++",\"approach\":"++show approach++",\"changes\":"++show changes++"}\n"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") order
  writeFile (out++"/manifest.json") manifest
  actualOrder <- readFile (out++"/orders.csv")
  actualManifest <- readFile (out++"/manifest.json")
  unless (actualOrder==order && actualManifest==manifest) $ fail "Submission readback mismatch"
  case lines actualOrder of
    ["side,quantity"] -> pure ()
    ["side,quantity",row] -> case split row of
      ["buy",s] -> case (readMaybe s :: Maybe Double) of
        Just x | x>0 && not (isNaN x || isInfinite x) && x*last ps*cost<=1000 -> pure ()
        _ -> fail "Invalid quantity"
      _ -> fail "Invalid order"
    _ -> fail "Invalid CSV"
  writeFile "/workspace/paper_3f23b0730060_m1/decision.txt" (show (edge, f1,f7,b,m,g1,g7,c,n)++"\n"++actualOrder++actualManifest)
  putStrLn ("Source "++ref++"; forecast net edge "++show (edge-(cost-1)))
  putStrLn ("Readback verified both submission files. "++if enter then "Buy quantity "++show q else "Valid cash hold.")
