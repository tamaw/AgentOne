{-# LANGUAGE BangPatterns #-}
module FleetOld where
import Data.Bits
import Data.Word
import Data.List
import Data.Array.ST
import Data.Array.Unboxed
import Control.Monad
import Control.Monad.ST
type Mask = Word64
mask :: [Int] -> Mask
mask = foldl' setBit 0
placements :: Int -> [(Mask,[Int])]
placements n = [(mask cs,cs) | r <- [0..7], c <- [0..7], (dr,dc) <- [(0,1),(1,0)], r+(n-1)*dr<8,c+(n-1)*dc<8,let cs=[(r+i*dr)*8+c+i*dc | i<-[0..n-1]]]
mix :: Word64 -> Word64
mix x = let a=(x `xor` (x `shiftR` 30))*0xbf58476d1ce4e5b9; b=(a `xor` (a `shiftR` 27))*0x94d049bb133111eb in b `xor` (b `shiftR` 31)
fleetBase :: Int -> Int -> [[Int]]
fleetBase seed rnd = go [4,3,2] 0 (mix (fromIntegral seed + fromIntegral rnd*1234567)) where
 go [] _ _ = []
 go (n:ns) used x = let ps=filter (\(m,_) -> m .&. used==0) (placements n); y=mix (x+0x9e3779b97f4a7c15); (m,cs)=ps !! fromIntegral (y `mod` fromIntegral (length ps)) in cs:go ns (used .|. m) y
type Shot = (Int,String,[Int])
choose :: Int -> Int -> [Shot] -> Int
choose seed rnd shots = if null available then 0 else maximumBy cmp available where
 tried=mask [c | (c,_,_)<-shots,c>=0,c<64]
 sunkLists=nub [sort ss | (_,_,ss)<-shots,not(null ss)]
 dead=mask (concat sunkLists)
 misses=mask [c | (c,r,_)<-shots,r=="miss"]
 hits=mask [c | (c,r,_)<-shots,r=="hit" || r=="sunk"] .&. complement dead
 lens=foldl' (flip delete) [4,3,2] (map length sunkLists)
 options=[[m | (m,_)<-placements n,m .&. (dead .|. misses)==0] | n<-lens]
 counts :: UArray Int Int
 counts=runSTUArray $ do
  a<-newArray (0,63) 0
  let add !m | m==0 = pure ()
             | otherwise = do
                let c=countTrailingZeros m
                v<-readArray a c
                writeArray a c (v+1)
                add (clearBit m c)
      walk [] !used = when (hits .&. complement used==0) (add (used .&. complement tried))
      walk (ps:rest) !used = forM_ ps $ \p -> when (p .&. used==0) (walk rest (used .|. p))
  walk options 0
  pure a
 available=[c | c<-[0..63],not(testBit tried c)]
 cmp a b=compare (counts!a, tie a) (counts!b,tie b)
 tie c=mix (fromIntegral seed + fromIntegral rnd*98765431 + fromIntegral c*123456789)

edgeFleet n seed round = foldl1 better [fleetBase (seed+k*7919) round | k<-[0..n-1]]
 where
 score ss = sum [let r=c `div` 8; q=c `mod` 8 in (2*r-7)^2+(2*q-7)^2 | c<-concat ss]
 better a b = if score a>=score b then a else b

fleet = edgeFleet 64
