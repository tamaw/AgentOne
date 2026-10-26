module Main where
import StrategyV1
import System.Environment
import Text.Printf
import Control.Monad
import Text.Read
split s=case break(==',') s of (a,[])->[a]; (a,_:b)->a:split b
finite x=not(isNaN x || isInfinite x)
parse s=case readMaybe s of Just x | finite x -> pure x; _ -> fail "Invalid numeric input"
main=do
 args<-getArgs
 case args of
  [bars,cashText,unitsText,out]->do
   input<-lines <$> readFile bars
   when(null input || head input/="t,close,volume") (fail "Expected t,close,volume header")
   let rows=map split (filter(not.null)(tail input))
   when(null rows || any ((/=3).length) rows) (fail "Invalid or empty bar history")
   ps<-mapM (parse . (!!1)) rows
   cash<-parse cashText; units<-parse unitsText
   unless(all (>0) ps && cash>=0 && units>=0) (fail "Positive prices and nonnegative cash/units required")
   let f=features(reverse ps); s=signal ConsensusV1 f (units>0)
       q=buyQuantity ConsensusV1 f 0.001 0.0005 cash
       order=case s of Buy | q>0 && finite q -> printf "buy,%.10f\n" q; Sell | units>0 -> printf "sell,%.10f\n" (units::Double); _ -> ""
   writeFile out ("side,quantity\n"++order)
   print f; print s
  _->fail "Expected bars cash units output-orders arguments; offline order generation only"
