module Main where
import System.IO
import Data.Char (toLower)
import Data.List (isPrefixOf)
import Control.Exception
main :: IO ()
main = do
 hSetBuffering stdin NoBuffering
 first <- getLine
 headers <- gather
 let sizes = [read (drop 15 x) :: Int | x <- headers, "content-length:" `isPrefixOf` map toLower x]
 let n = min 8192 (if null sizes then 0 else head sizes)
 body <- sequence (replicate n (hGetChar stdin))
 if "POST /message " `isPrefixOf` first then appendFile "/workspace/.runs/direct-chat/inbox.log" (body ++ "\n") else pure ()
 result <- if "GET /messages " `isPrefixOf` first then catch (readFile "/workspace/.runs/direct-chat/inbox.log") (\e -> let _ = e :: IOException in pure "") else pure "ACCEPTED\n"
 putStr ("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\n" ++ result)
gather = do
 x <- getLine
 if x == "\r" || null x then pure [] else (x:) <$> gather
