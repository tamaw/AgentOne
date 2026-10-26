module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  (_,o,e) <- readProcessWithExitCode "sh" ["-c", "cd /workspace/.runs/battleships-1792363073 && python3 - <<'PY'\np='Player.hs'\ns=open(p).read()\na=s.index('bestShot :: Req -> Int')\nb=s.index('\\nmain=do',a)\nnew=r'''bestShot :: Req -> Int\nbestShot q =\n let ss=shots q\n     tried=mask [c|(c,_,_)<-ss]\n     sunkCells=concat [z|(_,_,z)<-ss]\n     sunkM=mask sunkCells\n     sunkLens=map length $ filter (not.null) [z|(_,_,z)<-ss]\n     rems=foldl' (flip delete) [4,3,2] sunkLens\n     hitM=mask [c|(c,res,z)<-ss,res==\"hit\",null z]\n     bad=mask [c|(c,res,_ )<-ss,res==\"miss\"] .|. sunkM\n     ps=concatMap placements rems\n     ok p=p .&. bad==0 && (hitM==0 || p .&. hitM/=0)\n     score=foldl' (\\a p->if ok p then add (p .&. complement tried) a else a) (replicate 64 0) ps\n     avail=[i|i<-[0..63],not(testBit tried i)]\n     mx=maximum (map (score!!) avail)\n in head [i|i<-avail,score!!i==mx]\n'''\nopen(p,'w').write(s[:a]+new+s[b:])\nPY\ncp Player.hs versions/Player-v2-fast.hs\nstack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player && ./eval\nprintf '%s\\n' '{\"phase\":\"place\",\"seed\":123,\"round\":1}' '{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[]}' '{\"phase\":\"shoot\",\"seed\":5,\"round\":2,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]},{\"cell\":1,\"result\":\"sunk\",\"sunk\":[1,2]}]}' | ./player"] ""
  putStrLn (take 12000 (o ++ e))
  pure True