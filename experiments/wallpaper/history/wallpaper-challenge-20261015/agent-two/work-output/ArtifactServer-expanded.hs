{-# LANGUAGE ForeignFunctionInterface #-}
module Main where
import Foreign hiding (void)
import Foreign.C
import System.Posix.IO
import System.Posix.Types
import System.IO
import qualified Data.ByteString as B
import Control.Exception
import Control.Monad
import Data.List
import System.Timeout
foreign import ccall unsafe "socket" sock :: CInt -> CInt -> CInt -> IO CInt
foreign import ccall unsafe "setsockopt" setOpt :: CInt -> CInt -> CInt -> Ptr () -> CInt -> IO CInt
foreign import ccall unsafe "bind" bindSock :: CInt -> Ptr () -> CInt -> IO CInt
foreign import ccall unsafe "listen" listenSock :: CInt -> CInt -> IO CInt
foreign import ccall safe "accept" acceptSock :: CInt -> Ptr () -> Ptr () -> IO CInt
main = do
 s <- sock 2 1 0
 alloca (\p -> poke p (1::CInt) >> setOpt s 1 2 (castPtr p) 4) >>= \r -> when (r/=0) (error "setsockopt")
 b <- allocaBytes 16 $ \p -> do
  fillBytes p 0 16; pokeByteOff p 0 (2::Word16); pokeByteOff p 2 (168::Word8); pokeByteOff p 3 (115::Word8); bindSock s (castPtr p) 16
 when (b/=0) $ error "bind"
 listenSock s 8
 forever $ do
  fd <- acceptSock s nullPtr nullPtr
  when (fd>=0) $ do
   h <- fdToHandle (Fd fd)
   void (timeout 10000000 (serve h)) `catch` (\e -> hPutStrLn stderr (show (e::IOException)))
   hClose h `catch` (\(_::IOException) -> pure ())
serve h = do
 hSetBuffering h NoBuffering
 line <- hGetLine h
 let path=case words line of (_:p:_) -> p; _ -> "/"
 let allowed=["/initial.png","/preview.png","/final.png","/scene.py","/analysis.txt","/framing.py","/compose.py","/final-scene.py","/final-audit.json","/evolution-contact-sheet.png"]
 if path `elem` allowed then do
  bytes <- B.readFile ("/workspace/artifacts/wallpaper-challenge"++path)
  hPutStr h ("HTTP/1.1 200 OK\r\nContent-Length: "++show (B.length bytes)++"\r\nConnection: close\r\n\r\n"); B.hPut h bytes
 else hPutStr h "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
