import System.Process
import System.Exit
import Data.Time.Clock
main=do
 let q="{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]},{\"cell\":9,\"result\":\"hit\",\"sunk\":[]},{\"cell\":17,\"result\":\"miss\",\"sunk\":[]},{\"cell\":18,\"result\":\"miss\",\"sunk\":[]}]}\n"
 t<-getCurrentTime
 (x,a,b)<-readProcessWithExitCode "./player" [] q
 u<-getCurrentTime
 print (x,a,realToFrac (diffUTCTime u t)::Double,b)
