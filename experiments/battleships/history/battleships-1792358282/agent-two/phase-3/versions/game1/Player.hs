{-# LANGUAGE OverloadedStrings #-}
module Main where
import Fleet
import Data.Aeson
import Data.Aeson.Types
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.ByteString.Char8 as S
import System.IO
import Control.Monad
import Control.Exception
parseShot :: Value -> Parser Shot
parseShot=withObject "shot" $ \o -> (,,) <$> o .: "cell" <*> o .: "result" <*> o .:? "sunk" .!= []
respond :: Value -> Parser Value
respond=withObject "request" $ \o -> do
 phase<-o .: "phase" :: Parser String
 seed<-o .:? "seed" .!= 0
 rnd<-o .:? "round" .!= 0
 if phase=="place" then pure $ object ["ships" .= fleet seed rnd] else do
  vs<-o .:? "shots" .!= []
  ss<-mapM parseShot vs
  pure $ object ["shot" .= choose seed rnd ss]
main :: IO ()
main=do
 hSetBuffering stdout LineBuffering
 let loop=do
      end<-hIsEOF stdin
      unless end $ do
       l<-S.getLine
       let result= eitherDecodeStrict' l >>= parseEither respond
       B.putStrLn $ encode $ either (const (object ["shot" .= (0::Int)])) id result
       hFlush stdout
       loop
 loop
