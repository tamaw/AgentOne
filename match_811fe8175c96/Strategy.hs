module Strategy where
average xs = sum xs / fromIntegral (length xs)
sma n xs = average (drop (length xs-n) xs)
momentum n xs = last xs / (xs !! (length xs-1-n)) - 1
bullish xs = length xs >= 40 && last xs > sma 20 xs && sma 10 xs > sma 20 xs && sma 20 xs > sma 40 xs && momentum 21 xs > 0
targetFraction xs = if bullish xs then 0.85 else 0.0
