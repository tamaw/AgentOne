module Main where
import qualified Revision as R
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
 [bars,target,cashS,unitsS,roundS,evidence] <- getArgs
 raw <- readFile bars
 let ls = lines raw
 unless (not(null ls) && head ls == "t,close,volume") (fail "Invalid public bars header")
 let rows = map split (filter (not.null) (tail ls))
 unless (all ((==3).length) rows) (fail "Invalid bars rows")
 let prices = map (read . (!!1)) rows :: [Double]
     cash = read cashS :: Double
     units = read unitsS :: Double
 unless (length prices>=41 && all (\p -> p>0 && not(isNaN p || isInfinite p)) prices && all (\x -> x>=0 && not(isNaN x || isInfinite x)) [cash,units]) (fail "Invalid public inputs")
 let decision = R.order R.RevisionV1 0.0005 prices cash units (units==0)
     body = case decision of R.Hold -> ""; R.Buy q -> printf "buy,%.8f\n" q; R.Sell q -> "sell," ++ show q ++ "\n"
     ps = reverse prices
     p = head ps
     r k = p/(ps!!k)-1
     dist = p/(sum(take 20 ps)/20)-1
     features = printf "round=%s; t=%s; close=%.10f; return20=%.8f; return40=%.8f; SMA20-distance=%.8f; cash=%.12f; units=%.12f; decision=%s" roundS (head(last rows)) p (r 20) (r 40) dist cash units (show decision)
     ref = "/workspace/strategies/paper_63d59f6ee3e5/agent-two/Strategy.hs; dependency Revision.hs; source hashes: provenance.sha256 in same directory"
     approach = "Frozen experimental RevisionV1 on supplied public closes only: flat entry requires arithmetic returns20 and40 and close/SMA20-1 all >0.003; existing long exits only when all three <-0.003; otherwise deliberate hold, no topups. Buy allocation reserves max(12%,4*sampleSD40logreturns), includes 5bps slippage and 10bps fee, floors units to 1e-8. Unknown next close can still make a buy infeasible. Sell never exceeds stated holdings. " ++ features
     changes = "Actual Revision.hs read and copied byte-for-byte from /workspace/strategies/paper_e89d0022809c/agent-two/Revision.hs, verified against /workspace/strategies/paper_be01d1611e99/agent-two/offline-v1/Revision.hs and historical shared collaboration/agent-two/Revision.hs plus later own 05b62b926174 and aef4ace3cdbf copies. Hashes recorded in provenance.sha256. Prior harness reported peer-derived 20/40 confirmation and volatility reserve; this run independently verifies frozen shared code equality, not all historical claims or improved performance. Algorithm, thresholds and sizing unchanged. New Haskell submission harness explicitly creates and writes BOTH assigned files for every decision including HOLD, reads both back and checks equality; external JSON/CSV schema validation follows execution. This is an operational change, not proven trading improvement. Five-round independent run starts with 1000 once; later balances come only from routine. No claim of unseen/nonoverlapping history. No peer current submissions accessed. Evidence reviewed for this round: " ++ evidence
     orders = "side,quantity\n" ++ body
     manifest = "{\"code_ref\":" ++ show ref ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
 createDirectoryIfMissing True target
 writeFile (target++"/orders.csv") orders
 writeFile (target++"/manifest.json") manifest
 forM_ [("orders.csv",orders),("manifest.json",manifest)] $ \(name,expected) -> do
   exists <- doesFileExist (target++"/"++name)
   unless exists (fail ("Missing "++name))
   actual <- readFile (target++"/"++name)
   unless (actual==expected) (fail ("Readback mismatch "++name))
 putStrLn features
 putStrLn "Both assigned files explicitly written and read back; pending independent schema validation."
