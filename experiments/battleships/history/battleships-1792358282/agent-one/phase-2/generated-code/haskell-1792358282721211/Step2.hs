module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace"
  s <- readFile "SYSTEM.md"
  putStrLn s
  let dir = "/workspace/.runs/battleships-1792358282"
  createDirectoryIfMissing True dir
  setCurrentDirectory dir
  writeFile "Player.hs" $ unlines
    [ "{-# LANGUAGE OverloadedStrings #-}"
    , "module Main where"
    , "import Data.Aeson"
    , "import qualified Data.ByteString.Lazy.Char8 as B"
    , "import Data.Bits"
    , "import Data.Word"
    , "import Data.List"
    , "import Data.Ord"
    , "import Data.Array.Unboxed"
    , "import Data.Array.ST"
    , "import Control.Monad"
    , "import Control.Monad.ST"
    , "import System.IO"
    , "import Control.Exception"
    , "data Shot = Shot Int String [Int] deriving Show"
    , "instance FromJSON Shot where parseJSON = withObject \"shot\" $ \\o -> Shot <$> o .: \"cell\" <*> o .: \"result\" <*> o .:? \"sunk\" .!= []"
    , "data Req = Req String Int Int [Shot]"
    , "instance FromJSON Req where parseJSON = withObject \"req\" $ \\o -> Req <$> o .: \"phase\" <*> o .:? \"seed\" .!= 0 <*> o .:? \"round\" .!= 0 <*> o .:? \"shots\" .!= []"
    , "mask :: [Int] -> Word64"
    , "mask = foldl' setBit 0"
    , "placements :: Int -> [(Word64,[Int])]"
    , "placements n = [(mask cs,cs) | r <- [0..7], c <- [0..7], d <- [1,8], (if d==1 then c else r)+n<=8, let cs=[r*8+c+k*d|k<-[0..n-1]]]"
    , "mix :: Word64 -> Word64"
    , "mix x = let a=(x `xor` (x `shiftR` 30))*0xbf58476d1ce4e5b9; b=(a `xor` (a `shiftR` 27))*0x94d049bb133111eb in b `xor` (b `shiftR` 31)"
    , "place :: Int -> Int -> [[Int]]"
    , "place seed rnd = go 0 (mix (fromIntegral seed + fromIntegral rnd*0x9e3779b97f4a7c15)) [4,3,2] where"
    , " go _ _ [] = []"
    , " go used x (n:ns) = let ps=filter (\\(m,_) -> m .&. used==0) (placements n); (m,cs)=ps !! fromIntegral (x `mod` fromIntegral (length ps)) in cs:go (used .|. m) (mix (x+0x9e3779b97f4a7c15)) ns"
    , "choose :: Bool -> [Shot] -> Int"
    , "choose improved shots = maximumBy (comparing score) avail where"
    , " tried=mask [c|Shot c _ _<-shots]"
    , " sunkCells=mask (concat [ss|Shot _ _ ss<-shots])"
    , " hits=mask [c|Shot c res _<-shots,res/=\"miss\"] .&. complement sunkCells"
    , " blocked=mask [c|Shot c res _<-shots,res==\"miss\"] .|. sunkCells"
    , " lens=foldl' (flip delete) [4,3,2] [length ss|Shot _ _ ss<-shots,not(null ss)]"
    , " avail=[c|c<-[0..63],not(testBit tried c)]"
    , " options n=[(m,filter (not . testBit tried) cs)| (m,cs)<-placements n,m .&. blocked==0,m .&. complement tried/=0]"
    , " opts=map options lens"
    , " counts :: UArray Int Double"
    , " counts=runSTUArray $ do"
    , "   arr<-newArray (0,63) 0"
    , "   let walk used cells []=when (hits .&. complement used==0) $ forM_ cells $ \\(m,cs,n)->forM_ cs $ \\c->do"
    , "          v<-readArray arr c"
    , "          let w=if improved then (if m .&. hits/=0 then 1.0 else 0.85) * (1.0 + 0.25/fromIntegral n) else 1.0"
    , "          writeArray arr c (v+w)"
    , "       walk used cells (ps:rest)=forM_ ps $ \\(m,cs)->when (used .&. m==0) $ walk (used .|. m) ((m,cs,length cs):cells) rest"
    , "   walk 0 [] opts"
    , "   pure arr"
    , " smallest=if null lens then 2 else minimum lens"
    , " lattice c=(c `div` 8 + c `mod` 8) `mod` smallest==0"
    , " score c=(if improved && hits==0 && not (lattice c) then 0 else counts!c, counts!c, negate c)"
    , "respond :: Req -> Value"
    , "respond (Req phase seed rnd shots) | phase==\"place\" = object [\"ships\" .= place seed rnd]"
    , " | otherwise = object [\"shot\" .= (if length shots>=64 then 0 else choose True shots)]"
    , "main :: IO ()"
    , "main = do"
    , " hSetBuffering stdout LineBuffering"
    , " let loop=do"
    , "       eof<-isEOF"
    , "       unless eof $ do"
    , "         l<-B.getLine"
    , "         case eitherDecode l of"
    , "           Left _ -> B.putStrLn (encode (object [\"shot\" .= (0::Int)]))"
    , "           Right req -> B.putStrLn (encode (respond req))"
    , "         hFlush stdout"
    , "         loop"
    , " loop"
    ]
  (ec,out,err) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player > build.log 2>&1; cat build.log"] ""
  print ec
  putStrLn out
  putStrLn err
  pure True