module ResponseStream (readResponseStream) where
import Control.Exception
import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString as B
import qualified Data.IntMap.Strict as M
import qualified Data.Text as T
import System.IO
import System.IO.Error (isEOFError)

readResponseStream :: Handle -> IO Value
readResponseStream handle = loop [] Nothing Nothing M.empty
  where
    field key (Object o) = K.lookup key o
    field _ _ = Nothing
    message value = case field "error" value >>= field "message" of
      Just (String s) -> T.unpack s
      _ -> "Responses stream failed or was incomplete"
    finish items (Object o) =
      let existing=maybe [] id (parseMaybe (withObject "response" (.: "output")) (Object o) :: Maybe [Value])
      in Object $ K.insert "output" (toJSON $ M.elems $ M.union items (M.fromList $ zip [0..] existing)) o
    finish _ value = value
    consume [] completed failure items = (completed,failure,items)
    consume parts completed failure items =
      let raw=B.intercalate "\n" (reverse parts) in
      if raw == "[DONE]" then (completed,failure,items) else case eitherDecodeStrict' raw of
        Left _ -> (completed,Just "Malformed Responses stream event",items)
        Right event -> case field "type" event of
          Just (String "response.output_item.done") -> case (parseMaybe (withObject "event" (.: "output_index")) event :: Maybe Int,field "item" event) of
            (Just index,Just item) | index>=0 && index<4096 -> (completed,failure,M.insert index item items)
            _ -> (completed,Just "Invalid completed output item",items)
          Just (String "response.completed") -> case field "response" event of
            Just response -> (Just response,failure,items)
            Nothing -> (completed,Just "Completed stream event omitted its response",items)
          Just (String kind) | kind `elem` ["response.failed","response.incomplete","error"] -> (completed,Just $ message $ maybe event id (field "response" event),items)
          _ -> (completed,failure,items)
    loop parts completed failure items = do
      next <- (Just <$> B.hGetLine handle) `catch` \e -> if isEOFError e then pure Nothing else throwIO e
      case next of
        Nothing -> let (final,err,done)=consume parts completed failure items in
          case (final,err) of
            (_,Just problem) -> ioError $ userError problem
            (Just response,Nothing) -> pure $ finish done response
            _ -> ioError $ userError "Responses stream ended without response.completed"
        Just raw -> do
          let line = if not (B.null raw) && B.last raw == 13 then B.init raw else raw
          if B.null line then let (final,err,done)=consume parts completed failure items in loop [] final err done
          else if "data:" `B.isPrefixOf` line then do
            let rest=B.drop 5 line; chunk=if " " `B.isPrefixOf` rest then B.drop 1 rest else rest
            if B.length chunk + sum (map B.length parts) > 16777216
              then loop [] completed (Just "Responses stream event exceeded 16 MiB") items
              else loop (chunk:parts) completed failure items
          else if "{" `B.isPrefixOf` line then case eitherDecodeStrict' line of
            Right value -> loop parts completed (Just $ message value) items
            Left _ -> loop parts completed (Just "Invalid Responses stream") items
          else loop parts completed failure items
