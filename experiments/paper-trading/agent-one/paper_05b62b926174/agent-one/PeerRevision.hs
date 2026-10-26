module Revision where
data Model = OwnGeneralized | PeerManifest | RevisionV1 | ReserveHold | FullHold | CashOnly deriving (Eq,Show,Enum,Bounded)
data Order = Buy Double | Sell Double | Hold deriving (Eq,Show)
fee :: Double
fee = 0.001
roundDown :: Double -> Double
roundDown x = fromIntegral (floor (x*1e8) :: Integer)/1e8
order :: Model -> Double -> [Double] -> Double -> Double -> Bool -> Order
order model slip history cash units first
  | length history < 41 = Hold
  | model == CashOnly || model == FullHold = Hold
  | units > 0 = if sellSignal then Sell units else Hold
  | buySignal && q > 0 = Buy q
  | otherwise = Hold
  where
    ps = reverse (drop (length history-41) history)
    p = head ps
    r k = p / (ps !! k) - 1
    sma = sum (take 20 ps)/20
    distance = p/sma-1
    rs = zipWith (\a b -> log (a/b)) ps (tail ps)
    mu = sum rs/40
    sigma = sqrt (sum (map (\x -> (x-mu)^2) rs)/39)
    reserve = max 0.12 (4*sigma)
    alloc = if model == OwnGeneralized then 0.90 else 1/(1+reserve)
    q = let raw = cash*alloc / (p*(1+slip)*(1+fee)) in if model == PeerManifest then fromIntegral (floor (raw*1e10) :: Integer)/1e10 else roundDown raw
    buySignal = case model of
      OwnGeneralized -> r 10>0 && r 20>0
      PeerManifest -> r 20>0 && r 40>0
      RevisionV1 -> r 20>0.003 && r 40>0.003 && distance>0.003
      ReserveHold -> first
      _ -> False
    sellSignal = case model of
      OwnGeneralized -> distance<0 && r 10<0
      PeerManifest -> r 20<=0 || r 40<=0
      RevisionV1 -> r 20<(-0.003) && r 40<(-0.003) && distance<(-0.003)
      _ -> False
