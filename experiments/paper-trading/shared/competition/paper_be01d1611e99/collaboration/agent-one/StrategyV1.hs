module StrategyV1 where
data Mode = Original | ReserveOnly | ConsensusV1 | PeerReconstructed deriving (Show,Read,Eq,Enum,Bounded)
data Features = Features { historyCount :: Int, close :: Double, m10 :: Double, m20 :: Double, m40 :: Double, m60 :: Double, m120 :: Double, sma20 :: Double, sigma40 :: Double } deriving Show
data Signal = Buy | Sell | Hold deriving (Show,Eq)
features :: [Double] -> Features
features rev = Features n p (mom 10) (mom 20) (mom 40) (mom 60) (mom 120) (mean (take 20 rev)) vol
 where n=length rev; p=head rev; mom k=if n>k then log(p/(rev!!k)) else 0
       mean xs=sum xs/fromIntegral(length xs)
       rs=take 40 (zipWith (\a b->log(a/b)) rev (tail rev)); mu=mean rs
       vol=if length rs<2 then 0 else sqrt(sum(map (\r->(r-mu)^2) rs)/fromIntegral(length rs-1))
signal :: Mode -> Features -> Bool -> Signal
signal mode f held
 | historyCount f < required = Hold
 | not held && enter = Buy
 | held && leave = Sell
 | otherwise = Hold
 where required=if mode==ConsensusV1 then 121 else 41
       votes=length(filter (>0) [m20 f,m60 f,m120 f])
       enter=case mode of
         ConsensusV1 -> votes>=2
         PeerReconstructed -> m10 f>0 && m20 f>0
         _ -> m20 f>0 && m40 f>0
       leave=case mode of
         ConsensusV1 -> votes==0
         PeerReconstructed -> close f<sma20 f && m10 f<0
         _ -> not(m20 f>0 && m40 f>0)
reserve :: Mode -> Features -> Double
reserve Original f=max 0.12 (4*sigma40 f)
reserve PeerReconstructed _=1/0.9-1
reserve _ f=max 0.03 (3*sigma40 f)
buyQuantity :: Mode -> Features -> Double -> Double -> Double -> Double
buyQuantity mode f fee slip cash = fromIntegral(floor(raw*1e10)::Integer)/1e10
 where raw=cash/(close f*(1+reserve mode f)*(1+slip)*(1+fee))
