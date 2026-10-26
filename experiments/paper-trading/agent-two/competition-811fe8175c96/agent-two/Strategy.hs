module Strategy where
targetBuy :: [Double] -> Double -> Double
targetBuy ps cash
  | length ps < 31 = 0
  | p / (ps !! (length ps-15)) - 1 > 0.02 && p > avg (lastN 14) && p > avg (lastN 30) = fromIntegral (floor (0.90*cash/(p*1.0005*1.001)) :: Integer)
  | otherwise = 0
  where
    p = last ps
    lastN n = drop (length ps-n) ps
    avg xs = sum xs / fromIntegral (length xs)
