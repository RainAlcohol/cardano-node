{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Wno-orphans  #-}

module Cardano.Tracing.OrphanInstances.Network () where

import           Cardano.Prelude hiding (show)
import           Prelude (String, show)

import           Control.Monad.Class.MonadTime (DiffTime, Time (..))
import           Data.Text (pack)

import           Network.Mux (MuxTrace (..), WithMuxBearer (..))
import qualified Network.Socket as Socket (SockAddr)

import           Cardano.Tracing.ConvertTxId (ConvertTxId)
import           Cardano.Tracing.OrphanInstances.Common
import           Cardano.Tracing.Render

import           Ouroboros.Consensus.Block (ConvertRawHash (..), getHeader)
import           Ouroboros.Consensus.Ledger.SupportsMempool (GenTx, HasTxs (..), txId)
import           Ouroboros.Consensus.Node.Run (RunNode (..))
import           Ouroboros.Network.Block
import           Ouroboros.Network.BlockFetch.ClientState (TraceFetchClientState,
                     TraceLabelPeer (..))
import qualified Ouroboros.Network.BlockFetch.ClientState as BlockFetch
import           Ouroboros.Network.BlockFetch.Decision (FetchDecision, FetchDecline (..))
import           Ouroboros.Network.ConnectionId (ConnectionId (..))
import           Ouroboros.Network.ConnectionManager.Types (ExceptionInHandler (..))
import           Ouroboros.Network.Codec (AnyMessageAndAgency (..))
import           Ouroboros.Network.DeltaQ (GSV (..), PeerGSV (..))
import           Ouroboros.Network.KeepAlive (TraceKeepAliveClient (..))
import qualified Ouroboros.Network.NodeToClient as NtC
import           Ouroboros.Network.NodeToNode (ErrorPolicyTrace (..), TraceSendRecv (..),
                     WithAddr (..))
import qualified Ouroboros.Network.NodeToNode as NtN
import           Ouroboros.Network.Protocol.BlockFetch.Type (BlockFetch, Message (..))
import           Ouroboros.Network.Protocol.ChainSync.Type (ChainSync)
import qualified Ouroboros.Network.Protocol.ChainSync.Type as ChainSync
import           Ouroboros.Network.Protocol.LocalStateQuery.Type (LocalStateQuery)
import qualified Ouroboros.Network.Protocol.LocalStateQuery.Type as LocalStateQuery
import           Ouroboros.Network.Protocol.LocalTxSubmission.Type (LocalTxSubmission)
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Type as LocalTxSub
import           Ouroboros.Network.Protocol.TxSubmission.Type (Message (..), TxSubmission)
import           Ouroboros.Network.Snocket (LocalAddress (..))
import           Ouroboros.Network.Subscription (ConnectResult (..), DnsTrace (..),
                     SubscriberError (..), SubscriptionTrace (..), WithDomainName (..),
                     WithIPList (..))
import           Ouroboros.Network.TxSubmission.Inbound (TraceTxSubmissionInbound (..))
import qualified Ouroboros.Network.TxSubmission.Inbound as TxSubmission.Inbound
import           Ouroboros.Network.TxSubmission.Outbound (TraceTxSubmissionOutbound (..))
import           Ouroboros.Network.Diffusion (TraceLocalRootPeers, TracePublicRootPeers,
                   TracePeerSelection (..), DebugPeerSelection,
                   PeerSelectionActionsTrace (..), ConnectionManagerTrace (..),
                   ConnectionHandlerTrace (..), ServerTrace (..))
import           Ouroboros.Network.RethrowPolicy (ErrorCommand (..))

{- HLINT ignore "Use record patterns" -}

--
-- * instances of @HasPrivacyAnnotation@ and @HasSeverityAnnotation@
--
-- NOTE: this list is sorted by the unqualified name of the outermost type.

instance HasPrivacyAnnotation NtC.HandshakeTr
instance HasSeverityAnnotation NtC.HandshakeTr where
  getSeverityAnnotation _ = Info


instance HasPrivacyAnnotation NtN.HandshakeTr
instance HasSeverityAnnotation NtN.HandshakeTr where
  getSeverityAnnotation _ = Info


instance HasPrivacyAnnotation NtN.AcceptConnectionsPolicyTrace
instance HasSeverityAnnotation NtN.AcceptConnectionsPolicyTrace where
  getSeverityAnnotation NtN.ServerTraceAcceptConnectionRateLimiting {} = Info
  getSeverityAnnotation NtN.ServerTraceAcceptConnectionHardLimit {} = Warning


instance HasPrivacyAnnotation (TraceFetchClientState header)
instance HasSeverityAnnotation (TraceFetchClientState header) where
  getSeverityAnnotation BlockFetch.AddedFetchRequest {} = Info
  getSeverityAnnotation BlockFetch.AcknowledgedFetchRequest {} = Info
  getSeverityAnnotation BlockFetch.StartedFetchBatch {} = Info
  getSeverityAnnotation BlockFetch.CompletedBlockFetch {} = Info
  getSeverityAnnotation BlockFetch.CompletedFetchBatch {} = Info
  getSeverityAnnotation BlockFetch.RejectedFetchBatch {} = Info
  getSeverityAnnotation BlockFetch.ClientTerminating {} = Notice


instance HasPrivacyAnnotation (TraceSendRecv a)
instance HasSeverityAnnotation (TraceSendRecv a) where
  getSeverityAnnotation _ = Debug


instance HasPrivacyAnnotation a => HasPrivacyAnnotation (TraceLabelPeer peer a)
instance HasSeverityAnnotation a => HasSeverityAnnotation (TraceLabelPeer peer a) where
  getSeverityAnnotation (TraceLabelPeer _p a) = getSeverityAnnotation a


instance HasPrivacyAnnotation [TraceLabelPeer peer (FetchDecision [Point header])]
instance HasSeverityAnnotation [TraceLabelPeer peer (FetchDecision [Point header])] where
  getSeverityAnnotation [] = Debug
  getSeverityAnnotation xs =
      maximum $ map (\(TraceLabelPeer _ a) -> fetchDecisionSeverity a) xs
    where
      fetchDecisionSeverity :: FetchDecision a -> Severity
      fetchDecisionSeverity fd =
        case fd of
          Left FetchDeclineChainNotPlausible     -> Debug
          Left FetchDeclineChainNoIntersection   -> Notice
          Left FetchDeclineAlreadyFetched        -> Debug
          Left FetchDeclineInFlightThisPeer      -> Debug
          Left FetchDeclineInFlightOtherPeer     -> Debug
          Left FetchDeclinePeerShutdown          -> Info
          Left FetchDeclinePeerSlow              -> Info
          Left FetchDeclineReqsInFlightLimit {}  -> Info
          Left FetchDeclineBytesInFlightLimit {} -> Info
          Left FetchDeclinePeerBusy {}           -> Info
          Left FetchDeclineConcurrencyLimit {}   -> Info
          Right _                                -> Info


instance HasPrivacyAnnotation (TraceTxSubmissionInbound txid tx)
instance HasSeverityAnnotation (TraceTxSubmissionInbound txid tx) where
  getSeverityAnnotation TxSubmission.Inbound.TxInboundTerminated = Notice
  getSeverityAnnotation TxSubmission.Inbound.TxInboundCannotRequestMoreTxs {} = Debug
  getSeverityAnnotation TxSubmission.Inbound.TxInboundCanRequestMoreTxs {} = Debug


instance HasPrivacyAnnotation (TraceTxSubmissionOutbound txid tx)
instance HasSeverityAnnotation (TraceTxSubmissionOutbound txid tx) where
  getSeverityAnnotation _ = Info


instance HasPrivacyAnnotation (TraceKeepAliveClient remotePeer)
instance HasSeverityAnnotation (TraceKeepAliveClient remotePeer) where
  getSeverityAnnotation _ = Info


instance HasPrivacyAnnotation (WithAddr addr ErrorPolicyTrace)
instance HasSeverityAnnotation (WithAddr addr ErrorPolicyTrace) where
  getSeverityAnnotation (WithAddr _ ev) = case ev of
    ErrorPolicySuspendPeer {} -> Warning -- peer misbehaved
    ErrorPolicySuspendConsumer {} -> Notice -- peer temporarily not useful
    ErrorPolicyLocalNodeError {} -> Error
    ErrorPolicyResumePeer {} -> Debug
    ErrorPolicyKeepSuspended {} -> Debug
    ErrorPolicyResumeConsumer {} -> Debug
    ErrorPolicyResumeProducer {} -> Debug
    ErrorPolicyUnhandledApplicationException {} -> Error
    ErrorPolicyUnhandledConnectionException {} -> Error
    ErrorPolicyAcceptException {} -> Error


instance HasPrivacyAnnotation (WithDomainName DnsTrace)
instance HasSeverityAnnotation (WithDomainName DnsTrace) where
  getSeverityAnnotation (WithDomainName _ ev) = case ev of
    DnsTraceLookupException {} -> Error
    DnsTraceLookupAError {} -> Error
    DnsTraceLookupAAAAError {} -> Error
    DnsTraceLookupIPv6First -> Debug
    DnsTraceLookupIPv4First -> Debug
    DnsTraceLookupAResult {} -> Debug
    DnsTraceLookupAAAAResult {} -> Debug


instance HasPrivacyAnnotation (WithDomainName (SubscriptionTrace Socket.SockAddr))
instance HasSeverityAnnotation (WithDomainName (SubscriptionTrace Socket.SockAddr)) where
  getSeverityAnnotation (WithDomainName _ ev) = case ev of
    SubscriptionTraceConnectStart {} -> Notice
    SubscriptionTraceConnectEnd {} -> Notice
    SubscriptionTraceConnectException _ e ->
        case fromException $ SomeException e of
             Just (_::SubscriberError) -> Debug
             Nothing -> Error
    SubscriptionTraceSocketAllocationException {} -> Error
    SubscriptionTraceTryConnectToPeer {} -> Info
    SubscriptionTraceSkippingPeer {} -> Info
    SubscriptionTraceSubscriptionRunning -> Debug
    SubscriptionTraceSubscriptionWaiting {} -> Debug
    SubscriptionTraceSubscriptionFailed -> Warning
    SubscriptionTraceSubscriptionWaitingNewConnection {} -> Debug
    SubscriptionTraceStart {} -> Debug
    SubscriptionTraceRestart {} -> Debug
    SubscriptionTraceConnectionExist {} -> Info
    SubscriptionTraceUnsupportedRemoteAddr {} -> Warning
    SubscriptionTraceMissingLocalAddress -> Warning
    SubscriptionTraceApplicationException _ e ->
        case fromException $ SomeException e of
             Just (_::SubscriberError) -> Debug
             Nothing -> Error
    SubscriptionTraceAllocateSocket {} -> Debug
    SubscriptionTraceCloseSocket {} -> Debug


instance HasPrivacyAnnotation (WithIPList (SubscriptionTrace Socket.SockAddr))
instance HasSeverityAnnotation (WithIPList (SubscriptionTrace Socket.SockAddr)) where
  getSeverityAnnotation (WithIPList _ _ ev) = case ev of
    SubscriptionTraceConnectStart _ -> Info
    SubscriptionTraceConnectEnd _ connectResult -> case connectResult of
      ConnectSuccess -> Info
      ConnectSuccessLast -> Notice
      ConnectValencyExceeded -> Warning
    SubscriptionTraceConnectException _ e ->
        case fromException $ SomeException e of
             Just (_::SubscriberError) -> Debug
             Nothing -> Error
    SubscriptionTraceSocketAllocationException {} -> Error
    SubscriptionTraceTryConnectToPeer {} -> Info
    SubscriptionTraceSkippingPeer {} -> Info
    SubscriptionTraceSubscriptionRunning -> Debug
    SubscriptionTraceSubscriptionWaiting {} -> Debug
    SubscriptionTraceSubscriptionFailed -> Error
    SubscriptionTraceSubscriptionWaitingNewConnection {} -> Notice
    SubscriptionTraceStart {} -> Debug
    SubscriptionTraceRestart {} -> Info
    SubscriptionTraceConnectionExist {} -> Notice
    SubscriptionTraceUnsupportedRemoteAddr {} -> Error
    SubscriptionTraceMissingLocalAddress -> Warning
    SubscriptionTraceApplicationException _ e ->
        case fromException $ SomeException e of
             Just (_::SubscriberError) -> Debug
             Nothing -> Error
    SubscriptionTraceAllocateSocket {} -> Debug
    SubscriptionTraceCloseSocket {} -> Info


instance HasPrivacyAnnotation (Identity (SubscriptionTrace LocalAddress))
instance HasSeverityAnnotation (Identity (SubscriptionTrace LocalAddress)) where
  getSeverityAnnotation (Identity ev) = case ev of
    SubscriptionTraceConnectStart {} -> Notice
    SubscriptionTraceConnectEnd {} -> Notice
    SubscriptionTraceConnectException {} -> Error
    SubscriptionTraceSocketAllocationException {} -> Error
    SubscriptionTraceTryConnectToPeer {} -> Notice
    SubscriptionTraceSkippingPeer {} -> Info
    SubscriptionTraceSubscriptionRunning -> Notice
    SubscriptionTraceSubscriptionWaiting {} -> Debug
    SubscriptionTraceSubscriptionFailed -> Warning
    SubscriptionTraceSubscriptionWaitingNewConnection {} -> Debug
    SubscriptionTraceStart {} -> Notice
    SubscriptionTraceRestart {} -> Notice
    SubscriptionTraceConnectionExist {} -> Debug
    SubscriptionTraceUnsupportedRemoteAddr {} -> Warning
    SubscriptionTraceMissingLocalAddress -> Warning
    SubscriptionTraceApplicationException {} -> Error
    SubscriptionTraceAllocateSocket {} -> Debug
    SubscriptionTraceCloseSocket {} -> Debug


instance Transformable Text IO (Identity (SubscriptionTrace LocalAddress)) where
  trTransformer = trStructuredText
instance HasTextFormatter (Identity (SubscriptionTrace LocalAddress)) where
  formatText _ = pack . show . toList


instance ToObject (Identity (SubscriptionTrace LocalAddress)) where
  toObject _verb (Identity ev) =
    mkObject [ "kind" .= ("SubscriptionTrace" :: String)
             , "event" .= show ev
             ]


instance HasPrivacyAnnotation (WithMuxBearer peer MuxTrace)
instance HasSeverityAnnotation (WithMuxBearer peer MuxTrace) where
  getSeverityAnnotation (WithMuxBearer _ ev) = case ev of
    MuxTraceRecvHeaderStart -> Debug
    MuxTraceRecvHeaderEnd {} -> Debug
    MuxTraceRecvStart {} -> Debug
    MuxTraceRecvEnd {} -> Debug
    MuxTraceSendStart {} -> Debug
    MuxTraceSendEnd -> Debug
    MuxTraceState {} -> Info
    MuxTraceCleanExit {} -> Notice
    MuxTraceExceptionExit {} -> Notice
    MuxTraceChannelRecvStart {} -> Debug
    MuxTraceChannelRecvEnd {} -> Debug
    MuxTraceChannelSendStart {} -> Debug
    MuxTraceChannelSendEnd {} -> Debug
    MuxTraceHandshakeStart -> Debug
    MuxTraceHandshakeClientEnd {} -> Info
    MuxTraceHandshakeServerEnd -> Debug
    MuxTraceHandshakeClientError {} -> Error
    MuxTraceHandshakeServerError {} -> Error
    MuxTraceRecvDeltaQObservation {} -> Debug
    MuxTraceRecvDeltaQSample {} -> Debug
    MuxTraceSDUReadTimeoutException -> Notice
    MuxTraceSDUWriteTimeoutException -> Notice
    MuxTraceStartEagerly _ _ -> Info
    MuxTraceStartOnDemand _ _ -> Info
    MuxTraceStartedOnDemand _ _ -> Info
    MuxTraceShutdown -> Debug

instance HasPrivacyAnnotation TraceLocalRootPeers
instance HasSeverityAnnotation TraceLocalRootPeers where
  getSeverityAnnotation _ = Info

instance HasPrivacyAnnotation TracePublicRootPeers
instance HasSeverityAnnotation TracePublicRootPeers where
  getSeverityAnnotation _ = Info

instance HasPrivacyAnnotation (TracePeerSelection addr)
instance HasSeverityAnnotation (TracePeerSelection addr) where
  getSeverityAnnotation ev =
    case ev of
      TraceLocalRootPeersChanged {} -> Notice
      TraceTargetsChanged        {} -> Notice
      TracePublicRootsRequest    {} -> Info
      TracePublicRootsResults    {} -> Info
      TracePublicRootsFailure    {} -> Error
      TraceGossipRequests        {} -> Debug
      TraceGossipResults         {} -> Debug
      TraceForgetColdPeers       {} -> Info
      TracePromoteColdPeers      {} -> Info
      TracePromoteColdFailed     {} -> Error
      TracePromoteColdDone       {} -> Info
      TracePromoteWarmPeers      {} -> Info
      TracePromoteWarmFailed     {} -> Error
      TracePromoteWarmDone       {} -> Info
      TraceDemoteWarmPeers       {} -> Info
      TraceDemoteWarmFailed      {} -> Error
      TraceDemoteWarmDone        {} -> Info
      TraceDemoteHotPeers        {} -> Info
      TraceDemoteHotFailed       {} -> Error
      TraceDemoteHotDone         {} -> Info
      TraceDemoteAsynchronous    {} -> Info
      -- 'TraceGovernorWakeup' is a warning, the governor should always have
      -- something to do or wait for some event.
      TraceGovernorWakeup        {} -> Warning

instance HasPrivacyAnnotation (DebugPeerSelection addr conn)
instance HasSeverityAnnotation (DebugPeerSelection addr conn) where
  getSeverityAnnotation _ = Debug

instance HasPrivacyAnnotation (PeerSelectionActionsTrace Socket.SockAddr)
instance HasSeverityAnnotation (PeerSelectionActionsTrace Socket.SockAddr) where
  getSeverityAnnotation ev =
   case ev of
     PeerStatusChanged {}       -> Info
     PeerStatusChangeFailure {} -> Error
     PeerMonitoringError {}     -> Error
     PeerMonitoringResult {}    -> Debug

instance HasPrivacyAnnotation (ConnectionManagerTrace addr connTrace)
instance HasSeverityAnnotation (ConnectionManagerTrace addr (ConnectionHandlerTrace versionNumber)) where
  getSeverityAnnotation ev =
    case ev of
      ErrorFromHandler {} -> Error
      ConnectTo {} -> Info -- TODO: Debug
      ConnectError {} -> Warning
      RethrownErrorFromHandler {} -> Error
      ConnectionHandlerTrace _ ev' ->
        case ev' of
          ConnectionHandlerHandshakeSuccess        -> Info
          ConnectionHandlerHandshakeClientError {} -> Error
          ConnectionHandlerHandshakeServerError {} -> Error
          ConnectionHandlerError ShutdownNode _ _  -> Critical
          ConnectionHandlerError ShutdownPeer _ _  -> Error
      IncludedConnection {} -> Debug
      NegotiatedConnection {} -> Info
      ConnectionNotFound {} -> Debug
      ReusedConnection {} -> Debug
      ConnectionFinished {} -> Debug
      ShutdownConnectionManager -> Debug
      ConnectionExists {} -> Warning

instance HasPrivacyAnnotation (ServerTrace addr versionNumber)
instance HasSeverityAnnotation (ServerTrace addr versionNumber) where
  getSeverityAnnotation ev =
    case ev of
      ServerAcceptConnection {}                    -> Debug
      ServerStartRespondersOnInboundConncetion {}  -> Debug
      ServerStartRespondersOnOutboundConnection {} -> Debug
      ServerAcceptError {}                         -> Error
      ServerAcceptPolicyTrace {}                   -> Notice
      ServerStarted {}                             -> Notice
      ServerStopped {}                             -> Notice
      ServerMiniProtocolRestarted {}               -> Info
      ServerMiniProtocolError {}                   -> Error
      ServerControlMessage {}                      -> Debug

--
-- | instances of @Transformable@
--
-- NOTE: this list is sorted by the unqualified name of the outermost type.

instance Transformable Text IO NtN.HandshakeTr where
  trTransformer = trStructuredText
instance HasTextFormatter NtN.HandshakeTr where
  formatText _ = pack . show . toList


instance Transformable Text IO NtC.HandshakeTr where
  trTransformer = trStructuredText
instance HasTextFormatter NtC.HandshakeTr where
  formatText _ = pack . show . toList


instance Transformable Text IO NtN.AcceptConnectionsPolicyTrace where
  trTransformer = trStructuredText
instance HasTextFormatter NtN.AcceptConnectionsPolicyTrace where
  formatText _ = pack . show . toList


instance Show peer
      => Transformable Text IO [TraceLabelPeer peer (FetchDecision [Point header])] where
  trTransformer = trStructuredText
instance HasTextFormatter [TraceLabelPeer peer (FetchDecision [Point header])] where
  formatText _ = pack . show . toList


instance (Show peer, HasPrivacyAnnotation a, HasSeverityAnnotation a, ToObject a)
      => Transformable Text IO (TraceLabelPeer peer a) where
  trTransformer = trStructuredText
instance HasTextFormatter (TraceLabelPeer peer a) where
  formatText _ = pack . show . toList


instance Transformable Text IO (TraceTxSubmissionInbound txid tx) where
  trTransformer = trStructuredText
instance HasTextFormatter (TraceTxSubmissionInbound txid tx) where
  formatText _ = pack . show . toList


instance (Show tx, Show txid)
      => Transformable Text IO (TraceTxSubmissionOutbound txid tx) where
  trTransformer = trStructuredText
instance HasTextFormatter (TraceTxSubmissionOutbound txid tx) where
  formatText _ = pack . show . toList


instance Show addr
    => Transformable Text IO (TraceKeepAliveClient addr) where
  trTransformer = trStructuredText
instance HasTextFormatter (TraceKeepAliveClient addr) where
    formatText _ = pack . show . toList


instance Show addr => Transformable Text IO (WithAddr addr ErrorPolicyTrace) where
  trTransformer = trStructuredText
instance HasTextFormatter (WithAddr addr ErrorPolicyTrace) where
  formatText _ = pack . show . toList


instance Transformable Text IO (WithDomainName (SubscriptionTrace Socket.SockAddr)) where
  trTransformer = trStructuredText
instance HasTextFormatter (WithDomainName (SubscriptionTrace Socket.SockAddr)) where
  formatText _ = pack . show . toList


instance Transformable Text IO (WithDomainName DnsTrace) where
  trTransformer = trStructuredText
instance HasTextFormatter (WithDomainName DnsTrace) where
  formatText _ = pack . show . toList


instance Transformable Text IO (WithIPList (SubscriptionTrace Socket.SockAddr)) where
  trTransformer = trStructuredText
instance HasTextFormatter (WithIPList (SubscriptionTrace Socket.SockAddr)) where
  formatText _ = pack . show . toList


instance (Show peer)
      => Transformable Text IO (WithMuxBearer peer MuxTrace) where
  trTransformer = trStructuredText
instance (Show peer)
      => HasTextFormatter (WithMuxBearer peer MuxTrace) where
  formatText (WithMuxBearer peer ev) = \_o ->
    "Bearer on " <> pack (show peer)
   <> " event: " <> pack (show ev)


instance Transformable Text IO TraceLocalRootPeers where
  trTransformer = trStructuredText
instance HasTextFormatter TraceLocalRootPeers where
    formatText _ = pack . show . toList

instance Transformable Text IO TracePublicRootPeers where
  trTransformer = trStructuredText
instance HasTextFormatter TracePublicRootPeers where
  formatText _ = pack . show . toList

instance Transformable Text IO (TracePeerSelection Socket.SockAddr) where
  trTransformer = trStructuredText
instance HasTextFormatter (TracePeerSelection Socket.SockAddr) where
  formatText _ = pack . show . toList

instance Show conn
      => Transformable Text IO (DebugPeerSelection Socket.SockAddr conn) where
  trTransformer = trStructuredText
instance HasTextFormatter (DebugPeerSelection Socket.SockAddr conn) where
  formatText _ = pack . show . toList

instance Transformable Text IO (PeerSelectionActionsTrace Socket.SockAddr) where
  trTransformer = trStructuredText
instance HasTextFormatter (PeerSelectionActionsTrace Socket.SockAddr) where
  formatText _ = pack . show . toList

instance (Show addr, Show versionNumber)
      => Transformable Text IO (ConnectionManagerTrace addr (ConnectionHandlerTrace versionNumber)) where
  trTransformer = trStructuredText
instance HasTextFormatter (ConnectionManagerTrace addr (ConnectionHandlerTrace versionNumber)) where
  formatText _ = pack . show . toList

instance (Show addr, Show versionNumber)
      => Transformable Text IO (ServerTrace addr versionNumber) where
  trTransformer = trStructuredText
instance HasTextFormatter (ServerTrace addr versionNumber) where
  formatText _ = pack . show . toList

--
-- | instances of @ToObject@
--
-- NOTE: this list is sorted by the unqualified name of the outermost type.

instance ( ConvertTxId blk
         , RunNode blk
         , HasTxs blk
         )
      => ToObject (AnyMessageAndAgency (BlockFetch blk)) where
  toObject MaximalVerbosity (AnyMessageAndAgency stok (MsgBlock blk)) =
    mkObject [ "kind" .= String "MsgBlock"
             , "agency" .= String (pack $ show stok)
             , "blockHash" .= renderHeaderHash (Proxy @blk) (blockHash blk)
             , "blockSize" .= toJSON (nodeBlockFetchSize (getHeader blk))
             , "txIds" .= toJSON (presentTx <$> extractTxs blk)
             ]
      where
        presentTx :: GenTx blk -> Value
        presentTx =  String . renderTxIdForVerbosity MaximalVerbosity . txId

  toObject _v (AnyMessageAndAgency stok (MsgBlock blk)) =
    mkObject [ "kind" .= String "MsgBlock"
             , "agency" .= String (pack $ show stok)
             , "blockHash" .= renderHeaderHash (Proxy @blk) (blockHash blk)
             , "blockSize" .= toJSON (nodeBlockFetchSize (getHeader blk))
             ]
  toObject _v (AnyMessageAndAgency stok MsgRequestRange{}) =
    mkObject [ "kind" .= String "MsgRequestRange"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _v (AnyMessageAndAgency stok MsgStartBatch{}) =
    mkObject [ "kind" .= String "MsgStartBatch"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _v (AnyMessageAndAgency stok MsgNoBlocks{}) =
    mkObject [ "kind" .= String "MsgNoBlocks"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _v (AnyMessageAndAgency stok MsgBatchDone{}) =
    mkObject [ "kind" .= String "MsgBatchDone"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _v (AnyMessageAndAgency stok MsgClientDone{}) =
    mkObject [ "kind" .= String "MsgClientDone"
             , "agency" .= String (pack $ show stok)
             ]

instance (forall result. Show (query result))
      => ToObject (AnyMessageAndAgency (LocalStateQuery blk query)) where
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgAcquire{}) =
    mkObject [ "kind" .= String "MsgAcquire"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgAcquired{}) =
    mkObject [ "kind" .= String "MsgAcquired"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgFailure{}) =
    mkObject [ "kind" .= String "MsgFailure"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgQuery{}) =
    mkObject [ "kind" .= String "MsgQuery"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgResult{}) =
    mkObject [ "kind" .= String "MsgResult"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgRelease{}) =
    mkObject [ "kind" .= String "MsgRelease"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgReAcquire{}) =
    mkObject [ "kind" .= String "MsgReAcquire"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalStateQuery.MsgDone{}) =
    mkObject [ "kind" .= String "MsgDone"
             , "agency" .= String (pack $ show stok)
             ]

instance ToObject (AnyMessageAndAgency (LocalTxSubmission tx err)) where
  toObject _verb (AnyMessageAndAgency stok LocalTxSub.MsgSubmitTx{}) =
    mkObject [ "kind" .= String "MsgSubmitTx"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalTxSub.MsgAcceptTx{}) =
    mkObject [ "kind" .= String "MsgAcceptTx"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalTxSub.MsgRejectTx{}) =
    mkObject [ "kind" .= String "MsgRejectTx"
             , "agency" .= String (pack $ show stok)
             ]
  toObject _verb (AnyMessageAndAgency stok LocalTxSub.MsgDone{}) =
    mkObject [ "kind" .= String "MsgDone"
             , "agency" .= String (pack $ show stok)
             ]

instance ToObject (AnyMessageAndAgency (ChainSync blk tip)) where
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgRequestNext{}) =
     mkObject [ "kind" .= String "MsgRequestNext"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgAwaitReply{}) =
     mkObject [ "kind" .= String "MsgAwaitReply"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgRollForward{}) =
     mkObject [ "kind" .= String "MsgRollForward"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgRollBackward{}) =
     mkObject [ "kind" .= String "MsgRollBackward"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgFindIntersect{}) =
     mkObject [ "kind" .= String "MsgFindIntersect"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgIntersectFound{}) =
     mkObject [ "kind" .= String "MsgIntersectFound"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgIntersectNotFound{}) =
     mkObject [ "kind" .= String "MsgIntersectNotFound"
              , "agency" .= String (pack $ show stok)
              ]
   toObject _verb (AnyMessageAndAgency stok ChainSync.MsgDone{}) =
     mkObject [ "kind" .= String "MsgDone"
              , "agency" .= String (pack $ show stok)
              ]

instance ToObject (FetchDecision [Point header]) where
  toObject _verb (Left decline) =
    mkObject [ "kind" .= String "FetchDecision declined"
             , "declined" .= String (pack (show decline))
             ]
  toObject _verb (Right results) =
    mkObject [ "kind" .= String "FetchDecision results"
             , "length" .= String (pack $ show $ length results)
             ]


instance ToObject NtC.HandshakeTr where
  toObject _verb (WithMuxBearer b ev) =
    mkObject [ "kind" .= String "LocalHandshakeTrace"
             , "bearer" .= show b
             , "event" .= show ev ]


instance ToObject NtN.HandshakeTr where
  toObject _verb (WithMuxBearer b ev) =
    mkObject [ "kind" .= String "HandshakeTrace"
             , "bearer" .= show b
             , "event" .= show ev ]


instance ToObject NtN.AcceptConnectionsPolicyTrace where
  toObject _verb (NtN.ServerTraceAcceptConnectionRateLimiting delay numOfConnections) =
    mkObject [ "kind" .= String "ServerTraceAcceptConnectionRateLimiting"
             , "delay" .= show delay
             , "numberOfConnection" .= show numOfConnections
             ]
  toObject _verb (NtN.ServerTraceAcceptConnectionHardLimit softLimit) =
    mkObject [ "kind" .= String "ServerTraceAcceptConnectionHardLimit"
             , "softLimit" .= show softLimit
             ]


instance (Show txid, Show tx)
      => ToObject (AnyMessageAndAgency (TxSubmission txid tx)) where
  toObject _verb (AnyMessageAndAgency stok (MsgRequestTxs txids)) =
    mkObject
      [ "kind" .= String "MsgRequestTxs"
      , "agency" .= String (pack $ show stok)
      , "txIds" .= String (pack $ show txids)
      ]
  toObject _verb (AnyMessageAndAgency stok (MsgReplyTxs txs)) =
    mkObject
      [ "kind" .= String "MsgReplyTxs"
      , "agency" .= String (pack $ show stok)
      , "txs" .= String (pack $ show txs)
      ]
  toObject _verb (AnyMessageAndAgency stok (MsgRequestTxIds _ _ _)) =
    mkObject
      [ "kind" .= String "MsgRequestTxIds"
      , "agency" .= String (pack $ show stok)
      ]
  toObject _verb (AnyMessageAndAgency stok (MsgReplyTxIds _)) =
    mkObject
      [ "kind" .= String "MsgReplyTxIds"
      , "agency" .= String (pack $ show stok)
      ]
  toObject _verb (AnyMessageAndAgency stok MsgDone) =
    mkObject
      [ "kind" .= String "MsgDone"
      , "agency" .= String (pack $ show stok)
      ]
  --TODO: Can't use 'MsgKThxBye' because NodeToNodeV_2 is not introduced yet.
  toObject _verb (AnyMessageAndAgency stok _) =
    mkObject
      [ "kind" .= String "MsgKThxBye"
      , "agency" .= String (pack $ show stok)
      ]


instance ConvertRawHash blk
      => ToObject (Point blk) where
  toObject _verb GenesisPoint =
    mkObject
      [ "kind" .= String "GenesisPoint" ]
  toObject verb (BlockPoint slot h) =
    mkObject
      [ "kind" .= String "BlockPoint"
      , "slot" .= toJSON (unSlotNo slot)
      , "headerHash" .= renderHeaderHashForVerbosity (Proxy @blk) verb h
      ]


instance ToObject SlotNo where
  toObject _verb slot =
    mkObject [ "kind" .= String "SlotNo"
             , "slot" .= toJSON (unSlotNo slot) ]


instance ToObject (TraceFetchClientState header) where
  toObject _verb BlockFetch.AddedFetchRequest {} =
    mkObject [ "kind" .= String "AddedFetchRequest" ]
  toObject _verb BlockFetch.AcknowledgedFetchRequest {} =
    mkObject [ "kind" .= String "AcknowledgedFetchRequest" ]
  toObject _verb BlockFetch.CompletedBlockFetch {} =
    mkObject [ "kind" .= String "CompletedBlockFetch" ]
  toObject _verb BlockFetch.CompletedFetchBatch {} =
    mkObject [ "kind" .= String "CompletedFetchBatch" ]
  toObject _verb BlockFetch.StartedFetchBatch {} =
    mkObject [ "kind" .= String "StartedFetchBatch" ]
  toObject _verb BlockFetch.RejectedFetchBatch {} =
    mkObject [ "kind" .= String "RejectedFetchBatch" ]
  toObject _verb (BlockFetch.ClientTerminating outstanding) =
    mkObject [ "kind" .= String "Terminated"
             , "outstanding" .= outstanding
             ]


instance Show peer
      => ToObject [TraceLabelPeer peer (FetchDecision [Point header])] where
  toObject MinimalVerbosity _ = emptyObject
  toObject _ [] = emptyObject
  toObject _ xs = mkObject
    [ "kind"  .= String "PeersFetch"
    , "peers" .= toJSON
      (foldl' (\acc x -> toObject MaximalVerbosity x : acc) [] xs) ]


instance (Show peer, ToObject a) => ToObject (TraceLabelPeer peer a) where
  toObject verb (TraceLabelPeer peerid a) =
    mkObject [ "peer" .= show peerid ] <> toObject verb a


instance ToObject (AnyMessageAndAgency ps)
      => ToObject (TraceSendRecv ps) where
  toObject verb (TraceSendMsg m) = mkObject
    [ "kind" .= String "Send" , "msg" .= toObject verb m ]
  toObject verb (TraceRecvMsg m) = mkObject
    [ "kind" .= String "Recv" , "msg" .= toObject verb m ]


instance ToObject (TraceTxSubmissionInbound txid tx) where
  toObject _verb TxSubmission.Inbound.TxInboundTerminated =
    mkObject [ "kind" .= String "TxInboundTerminated" ]
  toObject _verb (TxSubmission.Inbound.TxInboundCanRequestMoreTxs n) =
    mkObject [ "kind" .= String "TxInboundCanRequestMoreTxs"
             , "pipelined" .= n
             ]
  toObject _verb (TxSubmission.Inbound.TxInboundCannotRequestMoreTxs n) =
    mkObject [ "kind" .= String "TxInboundCannotRequestMoreTxs"
             , "pipelined" .= n
             ]


instance (Show txid, Show tx)
      => ToObject (TraceTxSubmissionOutbound txid tx) where
  toObject MaximalVerbosity (TraceTxSubmissionOutboundRecvMsgRequestTxs txids) =
    mkObject
      [ "kind" .= String "TraceTxSubmissionOutboundRecvMsgRequestTxs"
      , "txIds" .= String (pack $ show txids)
      ]
  toObject _verb (TraceTxSubmissionOutboundRecvMsgRequestTxs _txids) =
    mkObject
      [ "kind" .= String "TraceTxSubmissionOutboundRecvMsgRequestTxs"
      ]
  toObject MaximalVerbosity (TraceTxSubmissionOutboundSendMsgReplyTxs txs) =
    mkObject
      [ "kind" .= String "TraceTxSubmissionOutboundSendMsgReplyTxs"
      , "txs" .= String (pack $ show txs)
      ]
  toObject _verb (TraceTxSubmissionOutboundSendMsgReplyTxs _txs) =
    mkObject
      [ "kind" .= String "TraceTxSubmissionOutboundSendMsgReplyTxs"
      ]
  toObject _verb (TraceControlMessage controlMessage) =
    mkObject
      [ "kind" .= String "TraceControlMessage"
      , "controlMessage" .= String (pack $ show controlMessage)
      ]


instance Show remotePeer => ToObject (TraceKeepAliveClient remotePeer) where
  toObject _verb (AddSample peer rtt pgsv) =
    mkObject
      [ "kind" .= String "TraceKeepAliveClient AddSample"
      , "address" .= show peer
      , "rtt" .= rtt
      , "sampleTime" .= show (dTime $ sampleTime pgsv)
      , "outboundG" .= (realToFrac $ gGSV (outboundGSV pgsv) :: Double)
      , "inboundG" .= (realToFrac $ gGSV (inboundGSV pgsv) :: Double)
      ]
    where
      gGSV :: GSV -> DiffTime
      gGSV (GSV g _ _) = g

      dTime :: Time -> Double
      dTime (Time d) = realToFrac d

instance Show addr => ToObject (WithAddr addr ErrorPolicyTrace) where
  toObject _verb (WithAddr addr ev) =
    mkObject [ "kind" .= String "ErrorPolicyTrace"
             , "address" .= show addr
             , "event" .= show ev ]


instance ToObject (WithIPList (SubscriptionTrace Socket.SockAddr)) where
  toObject _verb (WithIPList localAddresses dests ev) =
    mkObject [ "kind" .= String "WithIPList SubscriptionTrace"
             , "localAddresses" .= show localAddresses
             , "dests" .= show dests
             , "event" .= show ev ]


instance ToObject (WithDomainName DnsTrace) where
  toObject _verb (WithDomainName dom ev) =
    mkObject [ "kind" .= String "DnsTrace"
             , "domain" .= show dom
             , "event" .= show ev ]


instance ToObject (WithDomainName (SubscriptionTrace Socket.SockAddr)) where
  toObject _verb (WithDomainName dom ev) =
    mkObject [ "kind" .= String "SubscriptionTrace"
             , "domain" .= show dom
             , "event" .= show ev ]


instance (Show peer) => ToObject (WithMuxBearer peer MuxTrace) where
  toObject _verb (WithMuxBearer b ev) =
    mkObject [ "kind" .= String "MuxTrace"
             , "bearer" .= show b
             , "event" .= show ev ]

instance ToObject TraceLocalRootPeers where
  toObject _verb ev =
    mkObject [ "kind" .= String "TraceLocalRootPeers"
             , "event" .= show ev ]

instance ToObject TracePublicRootPeers where
  toObject _verb ev =
    mkObject [ "kind" .= String "TracePublicRootPeers"
             , "event" .= show ev ]

instance ToObject (TracePeerSelection Socket.SockAddr) where
  toObject _verb ev =
    mkObject [ "kind" .= String "TracePeerSelection"
             , "event" .= show ev ]

instance Show peerConn => ToObject (DebugPeerSelection Socket.SockAddr peerConn) where
  toObject _verb ev =
    mkObject [ "kind" .= String "DebugPeerSelection"
             , "event" .= show ev ]

instance ToObject (PeerSelectionActionsTrace Socket.SockAddr) where
  toObject _verb ev =
    mkObject [ "kind" .= String "PeerSelectionAction"
             , "event" .= show ev ]

instance (Show addr, Show versionNumber)
      => ToObject (ConnectionManagerTrace addr (ConnectionHandlerTrace versionNumber)) where
  toObject _verb ev =
    case ev of
      IncludedConnection connId dir ->
        mkObject $ reverse $
          [ "kind" .= String "IncludedConnection"
          , "conectionId" .= String (pack . show $ connId)
          , "direction" .= String (pack . show $ dir)
          ]
      NegotiatedConnection connId dir ->
        mkObject
          [ "kind" .= String "NegotiatedConnection"
          , "connectionId" .= String (pack . show $ connId)
          , "direction" .= String (pack . show $ dir)
          ]
      ConnectTo (Just localAddress) remoteAddress ->
        mkObject
          [ "kind" .= String "ConnectTo"
          , "connectionId" .= String (pack . show $ ConnectionId { localAddress, remoteAddress })
          ]
      ConnectTo Nothing remoteAddress ->
        mkObject
          [ "kind" .= String "ConnectTo"
          , "remoteAddress" .= String (pack .show $ remoteAddress)
          ]
      ConnectError (Just localAddress) remoteAddress err ->
        mkObject
          [ "king" .= String "ConnectError"
          , "connectionId" .= String (pack . show $ ConnectionId { localAddress, remoteAddress })
          , "error" .= String (pack . show $ err)
          ]
      ConnectError Nothing remoteAddress err ->
        mkObject
          [ "king" .= String "ConnectError"
          , "remoteAddress" .= String (pack . show $ remoteAddress)
          , "error" .= String (pack . show $ err)
          ]
      ReusedConnection remoteAddress  dir ->
        mkObject
          [ "kind" .= String "ReusedConnection"
          , "remoteAddress" .= String (pack . show $ remoteAddress)
          , "direction" .= String (pack . show $ dir)
          ]
      ConnectionFinished connId dir ->
        mkObject
          [ "kind" .= String "ConnectionFinished"
          , "connectionId" .= String (pack . show $ connId)
          , "direction" .= String (pack . show $ dir)
          ]
      ErrorFromHandler connId err ->
        mkObject
          [ "kind" .= String "ErrorFromHandler"
          , "connectionId" .= String (pack . show $ connId)
          , "error" .= String (pack . show $ err)
          ]
      RethrownErrorFromHandler (ExceptionInHandler remoteAddress err) ->
        mkObject
          [ "kind" .= String "RethrownErrorFromHandler"
          , "remoteAddress" .= String (pack . show $ remoteAddress)
          , "error" .= String (pack . show $ err)
          ]
      ConnectionHandlerTrace connId a ->
        mkObject
          [ "kind" .= String "ConnectionHandler"
          , "connectionId" .= String (pack . show $ connId)
          -- TODO:  encode 'ConnectionHandlerTrace'
          , "connectionHandler" .= String (pack . show $ a)
          ]
      ShutdownConnectionManager ->
        mkObject
          [ "kind" .= String "ShutdownConnectionManager"
          ]
      ConnectionExists connId dir ->
        mkObject
          [ "kind" .= String "ConnectionExists"
          , "connectionId" .= String (pack . show $ connId)
          , "direction" .= String (pack . show $ dir)
          ]
      ConnectionNotFound remoteAddress dir ->
        mkObject
          [ "kind" .= String "ConnectionNotFound"
          , "remoteAddress" .= String (pack . show $ remoteAddress)
          , "direction" .= String (pack . show $ dir)
          ]

instance (Show addr, Show versionNumber)
      => ToObject (ServerTrace addr versionNumber) where
  -- TODO: a better 'ToObject' instance
  toObject _verb ev =
    mkObject [ "kind" .= String "ServerTrace"
             , "event" .= show ev ]
