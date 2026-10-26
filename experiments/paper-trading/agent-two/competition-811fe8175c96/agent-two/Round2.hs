module Round2 where
orders :: [Double] -> Double -> Double -> [(String,Double)]
orders ps cash units
  | length ps < 31 = []
  | momentum > 0.02 && p > mean 14 && p > mean 30 =
      if additional >= 1 then [("buy",additional)] else []
  | otherwise = []
  where
    p = last ps
    mean n = sum (drop (length ps-n) ps) / fromIntegral n
    momentum = p / (ps !! (length ps-15)) - 1
    target = fromIntegral (floor (0.90*(cash+units*p)/(p*1.0005*1.001)) :: Integer)
    additional = max 0 (target-units)
