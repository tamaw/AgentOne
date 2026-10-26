{-# LANGUAGE OverloadedStrings #-}
module A2ACompat (legacyCard, legacyRequest, legacyResponse) where
import Data.Aeson
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.Text as T
import qualified Data.Vector as V

get k (Object o) = maybe Null id (K.lookup k o)
get _ _ = Null
put k v (Object o) = Object (K.insert k v o)
put _ _ v = v
dropKey k (Object o) = Object (K.delete k o)
dropKey _ v = v
mapArray f (Array xs) = Array (V.map f xs)
mapArray _ v = v
mapField k f v = if get k v == Null then v else put k (f (get k v)) v
legacyCard card =
  let interfaces = get "supportedInterfaces" card
      url = case interfaces of Array xs | not (V.null xs) -> get "url" (V.head xs); _ -> Null
      legacy = case url of String s -> String (T.replace "/rpc" "/a2a/v0.3/rpc" s); _ -> Null
  in put "protocolVersion" (String "0.3.0") $ put "preferredTransport" (String "JSONRPC") $ put "url" legacy $ dropKey "supportedInterfaces" card
incoming m = mapField "parts" (mapArray (dropKey "kind")) $ mapField "role" role $ dropKey "kind" m where
  role (String "user") = String "ROLE_USER"
  role (String "agent") = String "ROLE_AGENT"
  role v = v
legacyRequest raw = case eitherDecodeStrict' raw of
  Left _ -> raw
  Right request -> L.toStrict $ encode $ case get "method" request of
    String "message/send" ->
      let params = get "params" request
          cfg = case get "configuration" params of Null -> object []; c -> c
          block = get "blocking" cfg == Bool True
          config = put "returnImmediately" (Bool (not block)) $ dropKey "blocking" cfg
          config' = if get "pushNotificationConfig" cfg == Null then config else put "taskPushNotificationConfig" (get "pushNotificationConfig" cfg) config
      in put "method" (String "SendMessage") $ put "params" (put "configuration" config' (mapField "message" incoming params)) request
    String "tasks/get" -> put "method" (String "GetTask") request
    String "tasks/cancel" -> put "method" (String "CancelTask") request
    _ -> request
part p = put "kind" (String "text") p
outgoing m = put "kind" (String "message") $ mapField "parts" (mapArray part) $ mapField "role" role m where
  role (String "ROLE_USER") = String "user"
  role (String "ROLE_AGENT") = String "agent"
  role v = v
task t = put "kind" (String "task") $ mapField "history" (mapArray outgoing) $ mapField "artifacts" (mapArray (mapField "parts" (mapArray part))) $ mapField "status" status t where
  status = mapField "message" outgoing . mapField "state" state
  state (String s) = String $ T.replace "_" "-" $ T.toLower $ maybe s id $ T.stripPrefix "TASK_STATE_" s
  state v = v
legacyResponse response = mapField "result" convert response where
  convert r | get "task" r /= Null = task (get "task" r)
            | get "message" r /= Null = outgoing (get "message" r)
            | get "status" r /= Null = task r
            | otherwise = r
