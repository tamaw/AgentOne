module Main where
import System.Environment
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import Control.Monad
import Data.List
import Numeric
import Text.Read

split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:r) -> a:split r
avg xs = sum xs / fromIntegral (length xs)
clamp lo hi x = max lo (min hi x)
num x = showFFloat (Just 10) x ""
main = do
  [input,out,src,archive] <- getArgs
  raw <- readFile input
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
  unless (length rows >= 25 && all ((==3) . length) rows) (fail "Invalid public bars")
  let ts = map (read . head) rows :: [Int]
      closes = map (read . (!!1)) rows :: [Double]
      volumes = map (read . (!!2)) rows :: [Double]
  unless (and (zipWith (<) ts (tail ts)) && all (\x -> x>0 && not (isNaN x || isInfinite x)) closes && all (>=0) volumes) (fail "Invalid observations")
  let logs = map log closes
      xs = init logs
      ys = tail logs
      mx = avg xs
      my = avg ys
      sxx = sum [(x-mx)^2 | x<-xs]
      sxy = sum (zipWith (\x y -> (x-mx)*(y-my)) xs ys)
      prior = 10 * sxx / fromIntegral (length xs)
      beta = clamp 0 0.98 ((sxy + prior*0.9)/(sxx+prior))
      alpha = my-beta*mx
      residuals = zipWith (\x y -> y-alpha-beta*x) xs ys
      noise = max 1e-8 (sum (map (^2) residuals)/fromIntegral (length residuals-2))
      predictions = iterate (\x -> alpha+beta*x) (last logs)
      variance = noise * sum [beta^(2*k) | k<-[0..5::Int]]
      cost = 1.0005*1.001
      edge = predictions!!7 - predictions!!1 - log cost
      allocation = clamp 0 0.95 (edge/(3*variance))
      desired = 1000*allocation/(last closes*cost)
      stressLimit = 1000/(maximum closes*1.35*cost)
      quantity = if edge > 0 then min desired stressLimit else 0
      orders = "side,quantity\n" ++ if quantity >= 1e-8 then "buy,"++num quantity++"\n" else ""
  (hc,ho,he) <- readProcessWithExitCode "sha256sum" [src] ""
  unless (hc == ExitSuccess) (fail ("Source hashing failed: "++he))
  let hash = head (words ho)
      approach = "Public-close-only regularized log-price AR(1); forecast decision+7 versus decision+1, deduct buy costs, size with forecast variance and a 35%-above-observed-maximum fill stress cash cap. Volume is validated but not a feature. No external observations or peer inputs."
      changes = "source=sha256:"++hash++"; parent=none (initial executable v1); effective_round=0. Hypothesis: bounded mean reversion can outweigh entry costs over the six close-to-mark intervals. Initial rules: AR slope prior 0.90 with 10 pseudo-observations, slope clipped [0,0.98], positive forecast edge after fee/slippage, variance penalty 3, allocation ceiling 0.95, stress price 1.35 times maximum supplied close. No previous tips exist; none adopted/rejected. New implementation, not a demonstrated or backtested improvement; no parameter search. One execution, no retry or repair."
      manifest = "{\n  \"code_ref\": "++show (src++"#sha256:"++hash)++",\n  \"approach\": "++show approach++",\n  \"changes\": "++show changes++"\n}\n"
  writeFile (archive </> "model-output.txt") (unlines ["beta="++show beta,"alpha="++show alpha,"noise="++show noise,"forecast_net_log_edge="++show edge,"allocation="++show allocation,"quantity="++show quantity,"source_sha256="++hash])
  writeFile (out </> "orders.csv") orders
  writeFile (out </> "manifest.json") manifest
  ro <- readFile (out </> "orders.csv")
  rm <- readFile (out </> "manifest.json")
  unless (ro == orders && rm == manifest) (fail "Submission readback mismatch; not repaired")
  let ol = lines ro
  unless (head ol == "side,quantity" && all (\r -> case split r of ["buy",q] -> case (readMaybe q :: Maybe Double) of Just n -> n>0 && not(isNaN n || isInfinite n); _ -> False; _ -> False) (tail ol)) (fail "Order readback invalid; not repaired")
  (jc,jo,je) <- readProcessWithExitCode "python3" ["-c", "import json,sys; d=json.load(open(sys.argv[1])); assert all(isinstance(d.get(k),str) and d[k] for k in ('code_ref','approach','changes')); print('Manifest JSON and required string fields verified.')",out </> "manifest.json"] ""
  unless (jc == ExitSuccess) (fail ("Manifest readback validation failed; not repaired: "++je))
  writeFile (archive </> "orders.csv") ro
  writeFile (archive </> "manifest.json") rm
  putStr jo
  putStrLn "Orders and manifest written once and readback-checked; source and input snapshots retained."
  putStrLn ("Executable source SHA256: "++hash)
