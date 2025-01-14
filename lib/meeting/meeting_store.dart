//Package imports
import 'package:clubhouse_clone/models/peer_track_node.dart';
import 'package:clubhouse_clone/services/token_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobx/mobx.dart';
import 'package:intl/intl.dart';

//Project imports
import 'package:hmssdk_flutter/hmssdk_flutter.dart';

import 'hms_sdk_interactor.dart';

part 'meeting_store.g.dart';

class MeetingStore = MeetingStoreBase with _$MeetingStore;

abstract class MeetingStoreBase extends ChangeNotifier
    with Store
    implements HMSUpdateListener, HMSActionResultListener {
  late HMSSDKInteractor _hmssdkInteractor;

  MeetingStoreBase() {
    _hmssdkInteractor = HMSSDKInteractor();
  }

  // HMSLogListener
  @observable
  bool isSpeakerOn = true;
  @observable
  HMSException? hmsException;
  @observable
  HMSRoleChangeRequest? roleChangeRequest;

  @observable
  bool isMeetingStarted = false;
  @observable
  bool isMicOn = true;

  @observable
  bool reconnecting = false;
  @observable
  bool reconnected = false;
  @observable
  bool isRoomEnded = false;
  @observable
  String event = '';

  @observable
  HMSTrackChangeRequest? hmsTrackChangeRequest;
  @observable
  List<HMSRole> roles = [];

  late int highestSpeakerIndex = -1;

  @observable
  ObservableList<HMSPeer> peers = ObservableList.of([]);

  @observable
  HMSPeer? localPeer;
  @observable
  HMSTrack? localTrack;

  @observable
  ObservableList<HMSTrack> tracks = ObservableList.of([]);

  @observable
  ObservableList<HMSTrack> audioTracks = ObservableList.of([]);

  @observable
  ObservableList<HMSMessage> messages = ObservableList.of([]);

  @observable
  ObservableMap<String, HMSTrackUpdate> trackStatus = ObservableMap.of({});

  @observable
  ObservableMap<String, HMSTrackUpdate> audioTrackStatus = ObservableMap.of({});

  @observable
  ObservableList<PeerTrackNode> peerTracks = ObservableList.of([]);

  HMSRoom? hmsRoom;

  int firstTimeBuild = 0;
  final DateFormat formatter = DateFormat('d MMM y h:mm:ss a');

  @action
  void addUpdateListener() {
    _hmssdkInteractor.addUpdateListener(this);
    // startHMSLogger(HMSLogLevel.VERBOSE, HMSLogLevel.VERBOSE);
    // addLogsListener();
  }

  @action
  void removeUpdateListener() {
    _hmssdkInteractor.removeUpdateListener(this);
    // removeLogsListener();
  }

  @action
  Future<bool> join(String user, String roomUrl) async {
    List<String?>? token =
        await TokenService().getToken(user: user, room: roomUrl);
    if (token == null) return false;
    HMSConfig config = HMSConfig(
      authToken: token[0]!,
      userName: user,
    );

    await _hmssdkInteractor.join(config: config);
    isMeetingStarted = true;
    return true;
  }

// TODO: add await to resolve crash on leave?
  void leave() async {
    _hmssdkInteractor.leave(hmsActionResultListener: this);
    isRoomEnded = true;
    peerTracks.clear();
  }

  @action
  Future<void> switchAudio() async {
    await _hmssdkInteractor.switchAudio(isOn: isMicOn);
    isMicOn = !isMicOn;
  }

  @action
  void sendBroadcastMessage(String message) {
    _hmssdkInteractor.sendBroadcastMessage(message, this);
  }

  @action
  void toggleSpeaker() {
    if (isSpeakerOn) {
      muteAll();
    } else {
      unMuteAll();
    }
    isSpeakerOn = !isSpeakerOn;
  }

  Future<bool> isAudioMute(HMSPeer? peer) async {
    // TODO: add permission checks in exmaple app UI
    return await _hmssdkInteractor.isAudioMute(peer);
  }

  @action
  void removePeer(HMSPeer peer) {
    peers.remove(peer);
  }

  @action
  void addPeer(HMSPeer peer) {
    if (!peers.contains(peer)) peers.add(peer);
  }

  @action
  void removeTrackWithTrackId(String trackId) {
    tracks.removeWhere((eachTrack) => eachTrack.trackId == trackId);
  }

  @action
  void removeTrackWithPeerIdExtra(String trackId) {
    var index = tracks.indexWhere((element) => trackId == element.trackId);
    tracks.removeAt(index);
  }

  @action
  void onRoleUpdated(int index, HMSPeer peer) {
    peers[index] = peer;
  }

  @action
  void updateRoleChangeRequest(HMSRoleChangeRequest roleChangeRequest) {
    this.roleChangeRequest = roleChangeRequest;
  }

  @action
  void addMessage(HMSMessage message) {
    messages.add(message);
  }

  @action
  void addTrackChangeRequestInstance(
      HMSTrackChangeRequest hmsTrackChangeRequest) {
    this.hmsTrackChangeRequest = hmsTrackChangeRequest;
  }

  @action
  void updatePeerAt(peer) {
    int index = peers.indexOf(peer);
    peers.removeAt(index);
    peers.insert(index, peer);
  }

  @override
  void onJoin({required HMSRoom room}) async {
    hmsRoom = room;
    for (HMSPeer each in room.peers!) {
      if (each.isLocal) {
        int index = peerTracks
            .indexWhere((element) => element.peer.peerId == each.peerId);
        if (index == -1) {
          peerTracks.add(PeerTrackNode(peer: each, name: each.name));
        }
        localPeer = each;
        addPeer(localPeer!);

        if (each.videoTrack != null) {
          if (each.audioTrack!.kind == HMSTrackKind.kHMSTrackKindAudio) {
            int index = peerTracks
                .indexWhere((element) => element.peer.peerId == each.peerId);
            peerTracks[index].audioTrack = each.audioTrack!;
            localTrack = each.audioTrack;
          }
        }
        break;
      }
    }
  }

  @override
  void onRoomUpdate({required HMSRoom room, required HMSRoomUpdate update}) {}

  @override
  void onPeerUpdate({required HMSPeer peer, required HMSPeerUpdate update}) {
    peerOperation(peer, update);
  }

  @override
  void onTrackUpdate(
      {required HMSTrack track,
      required HMSTrackUpdate trackUpdate,
      required HMSPeer peer}) {
    if (isSpeakerOn) {
      unMuteAll();
    } else {
      muteAll();
    }

    if (peer.isLocal) {
      localPeer = peer;
      if (track.kind == HMSTrackKind.kHMSTrackKindAudio) {
        localTrack = track;
        if (track.isMute) {
          isMicOn = false;
        }
      }
    }

    if (track.kind == HMSTrackKind.kHMSTrackKindAudio) {
      int index = peerTracks
          .indexWhere((element) => element.peer.peerId == peer.peerId);
      if (index != -1) peerTracks[index].audioTrack = track;
      return;
    }

    peerOperationWithTrack(peer, trackUpdate, track);
  }

  @override
  void onError({required HMSException error}) {
    hmsException = hmsException;
  }

  @override
  void onMessage({required HMSMessage message}) {
    addMessage(message);
  }

  @override
  void onRoleChangeRequest({required HMSRoleChangeRequest roleChangeRequest}) {
    updateRoleChangeRequest(roleChangeRequest);
  }

  HMSTrack? previousHighestVideoTrack;
  int previousHighestIndex = -1;
  @observable
  ObservableMap<String, String> observableMap = ObservableMap.of({});

  @override
  void onUpdateSpeakers({required List<HMSSpeaker> updateSpeakers}) {
    //Highest Speaker Update is currently Off
    // if (!isActiveSpeakerMode) {
    //   if (updateSpeakers.length == 0) {
    //     peerTracks.removeAt(highestSpeakerIndex);
    //     peerTracks.insert(highestSpeakerIndex, highestSpeaker);
    //     highestSpeaker = PeerTracKNode(peerId: "-1");
    //     return;
    //   }
    //
    //   highestSpeakerIndex = peerTracks.indexWhere((element) =>
    //       element.peerId.trim() == updateSpeakers[0].peer.peerId.trim());
    //
    //   print("index is $highestSpeakerIndex");
    //   if (highestSpeakerIndex != -1) {
    //     highestSpeaker = peerTracks[highestSpeakerIndex];
    //     peerTracks.removeAt(highestSpeakerIndex);
    //     peerTracks.insert(highestSpeakerIndex, highestSpeaker);
    //   } else {
    //     highestSpeaker = PeerTracKNode(peerId: "-1");
    //   }
    // } else {
    //   if (updateSpeakers.length == 0) {
    //     activeSpeakerPeerTracksStore.removeAt(0);
    //     activeSpeakerPeerTracksStore.insert(0, highestSpeaker);
    //     highestSpeaker = PeerTracKNode(peerId: "-1");
    //     return;
    //   }
    //   highestSpeakerIndex = activeSpeakerPeerTracksStore.indexWhere((element) =>
    //       element.peerId.trim() == updateSpeakers[0].peer.peerId.trim());
    //
    //   print("index is $highestSpeakerIndex");
    //   if (highestSpeakerIndex != -1) {
    //     highestSpeaker = activeSpeakerPeerTracksStore[highestSpeakerIndex];
    //     activeSpeakerPeerTracksStore.removeAt(highestSpeakerIndex);
    //     activeSpeakerPeerTracksStore.insert(0, highestSpeaker);
    //   } else {
    //     highestSpeaker = PeerTracKNode(peerId: "-1");
    //   }
    // }
  }

  @override
  void onReconnecting() {
    reconnected = false;
    reconnecting = true;
  }

  @override
  void onReconnected() {
    reconnecting = false;
    reconnected = true;
  }

  int trackChange = -1;

  @override
  void onChangeTrackStateRequest(
      {required HMSTrackChangeRequest hmsTrackChangeRequest}) {
    if (!hmsTrackChangeRequest.mute) {
      addTrackChangeRequestInstance(hmsTrackChangeRequest);
    }
  }

  void changeTracks(HMSTrackChangeRequest hmsTrackChangeRequest) {
    switchAudio();
  }

  @override
  void onRemovedFromRoom(
      {required HMSPeerRemovedFromPeer hmsPeerRemovedFromPeer}) {
    peerTracks.clear();
    isRoomEnded = true;
  }

  void changeRole(
      {required HMSPeer peer,
      required HMSRole roleName,
      bool forceChange = false}) {
    _hmssdkInteractor.changeRole(
        toRole: roleName,
        forPeer: peer,
        force: forceChange,
        hmsActionResultListener: this);
  }

  changeTrackState(HMSTrack track, bool mute) {
    return _hmssdkInteractor.changeTrackState(track, mute, this);
  }

  @action
  void peerOperation(HMSPeer peer, HMSPeerUpdate update) {
    switch (update) {
      case HMSPeerUpdate.peerJoined:
        if (peer.role.name.contains("hls-") == false) {
          int index = peerTracks
              .indexWhere((element) => element.peer.peerId == peer.peerId);
          if (index == -1) {
            peerTracks.add(PeerTrackNode(peer: peer, name: peer.name));
          }
        }
        addPeer(peer);
        break;
      case HMSPeerUpdate.peerLeft:
        peerTracks.removeWhere((element) => element.peer.peerId == peer.peerId);
        removePeer(peer);
        break;
      case HMSPeerUpdate.roleUpdated:
        updatePeerAt(peer);
        break;
      case HMSPeerUpdate.metadataChanged:
        break;
      case HMSPeerUpdate.nameChanged:
        if (peer.isLocal) {
          int localPeerIndex = peerTracks.indexWhere(
              (element) => element.peer.peerId == localPeer!.peerId);
          if (localPeerIndex != -1) {
            peerTracks[localPeerIndex].name = peer.name;
            localPeer = peer;
          }
        } else {
          int remotePeerIndex = peerTracks
              .indexWhere((element) => element.peer.peerId == peer.peerId);
          if (remotePeerIndex != -1) {
            peerTracks[remotePeerIndex].name = peer.name;
          }
        }

        updatePeerAt(peer);
        break;
      case HMSPeerUpdate.defaultUpdate:
        print("Some default update or untouched case");
        break;
      default:
        print("Some default update or untouched case");
    }
  }

  @action
  void peerOperationWithTrack(
      HMSPeer peer, HMSTrackUpdate update, HMSTrack track) {
    switch (update) {
      case HMSTrackUpdate.trackAdded:
        if (track.source == "REGULAR") {
          trackStatus[peer.peerId] = track.isMute
              ? HMSTrackUpdate.trackMuted
              : HMSTrackUpdate.trackUnMuted;
        }
        break;
      case HMSTrackUpdate.trackRemoved:
        peerTracks.removeWhere((element) => element.peer.peerId == peer.peerId);

        break;
      case HMSTrackUpdate.trackMuted:
        trackStatus[peer.peerId] = HMSTrackUpdate.trackMuted;
        break;
      case HMSTrackUpdate.trackUnMuted:
        trackStatus[peer.peerId] = HMSTrackUpdate.trackUnMuted;
        break;
      case HMSTrackUpdate.trackDescriptionChanged:
        break;
      case HMSTrackUpdate.trackDegraded:
        break;
      case HMSTrackUpdate.trackRestored:
        break;
      case HMSTrackUpdate.defaultUpdate:
        break;
      default:
        print("Some default update or untouched case");
    }
  }

  void endRoom(bool lock, String? reason) {
    _hmssdkInteractor.endRoom(lock, reason ?? "", this);
  }

  void removePeerFromRoom(HMSPeer peer) {
    _hmssdkInteractor.removePeer(peer, this);
  }

  void muteAll() {
    _hmssdkInteractor.muteAll();
  }

  void unMuteAll() {
    _hmssdkInteractor.unMuteAll();
  }

  // Logs are currently turned Off
  // @override
  // void onLogMessage({required dynamic HMSLogList}) async {
  // StaticLogger.logger?.v(HMSLogList.toString());
  //   FirebaseCrashlytics.instance.log(HMSLogList.toString());
  // }

  // void startHMSLogger(HMSLogLevel webRtclogLevel, HMSLogLevel logLevel) {
  //   HmsSdkManager.hmsSdkInteractor?.startHMSLogger(webRtclogLevel, logLevel);
  // }
  //
  // void addLogsListener() {
  //   HmsSdkManager.hmsSdkInteractor?.addLogsListener(this);
  // }
  //
  // void removeLogsListener() {
  //   HmsSdkManager.hmsSdkInteractor?.removeLogsListener(this);
  // }
  //
  // void removeHMSLogger() {
  //   HmsSdkManager.hmsSdkInteractor?.removeHMSLogger();
  // }

  Future<HMSPeer?> getLocalPeer() async {
    return await _hmssdkInteractor.getLocalPeer();
  }

  Future<HMSRoom?> getRoom() async {
    HMSRoom? room = await _hmssdkInteractor.getRoom();
    return room;
  }

  bool isRaisedHand = false;

  void changeMetadata() {
    isRaisedHand = !isRaisedHand;
    String value = isRaisedHand ? "true" : "false";
    _hmssdkInteractor.changeMetadata(
        metadata: "{\"isHandRaised\":$value}", hmsActionResultListener: this);
  }

  @override
  void onSuccess(
      {HMSActionResultListenerMethod methodType =
          HMSActionResultListenerMethod.unknown,
      Map<String, dynamic>? arguments}) {
    switch (methodType) {
      case HMSActionResultListenerMethod.leave:
        isRoomEnded = true;
        break;
      case HMSActionResultListenerMethod.changeTrackState:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeMetadata:
        print("raised hand");
        break;
      case HMSActionResultListenerMethod.endRoom:
        isRoomEnded = true;
        break;
      case HMSActionResultListenerMethod.removePeer:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.acceptChangeRole:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeRole:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeTrackStateForRole:
        event = arguments!['roles'] == null
            ? "Successfully Muted All"
            : "Successfully Muted Role";
        break;
      case HMSActionResultListenerMethod.startRtmpOrRecording:
        //TODO: HmsException?.code == 400(To see what this means)
        //isRecordingStarted = true;
        break;
      case HMSActionResultListenerMethod.stopRtmpAndRecording:
        break;
      case HMSActionResultListenerMethod.unknown:
        break;
      case HMSActionResultListenerMethod.changeName:
        event = "Name Changed to ${localPeer!.name}";
        break;
      case HMSActionResultListenerMethod.sendBroadcastMessage:
        var message = HMSMessage(
            sender: localPeer,
            message: arguments!['message'],
            type: arguments['type'],
            time: DateTime.now(),
            hmsMessageRecipient: HMSMessageRecipient(
                recipientPeer: null,
                recipientRoles: null,
                hmsMessageRecipientType: HMSMessageRecipientType.BROADCAST));
        addMessage(message);
        break;
      case HMSActionResultListenerMethod.sendGroupMessage:
        var message = HMSMessage(
            sender: localPeer,
            message: arguments!['message'],
            type: arguments['type'],
            time: DateTime.now(),
            hmsMessageRecipient: HMSMessageRecipient(
                recipientPeer: null,
                recipientRoles: arguments['roles'],
                hmsMessageRecipientType: HMSMessageRecipientType.GROUP));
        addMessage(message);
        break;
      case HMSActionResultListenerMethod.sendDirectMessage:
        var message = HMSMessage(
            sender: localPeer,
            message: arguments!['message'],
            type: arguments['type'],
            time: DateTime.now(),
            hmsMessageRecipient: HMSMessageRecipient(
                recipientPeer: arguments['peer'],
                recipientRoles: null,
                hmsMessageRecipientType: HMSMessageRecipientType.DIRECT));
        addMessage(message);
        break;
      case HMSActionResultListenerMethod.hlsStreamingStarted:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.hlsStreamingStopped:
        // TODO: Handle this case.
        break;

      case HMSActionResultListenerMethod.startScreenShare:
        break;

      case HMSActionResultListenerMethod.stopScreenShare:
        break;
    }
  }

  @override
  void onException(
      {HMSActionResultListenerMethod methodType =
          HMSActionResultListenerMethod.unknown,
      Map<String, dynamic>? arguments,
      required HMSException hmsException}) {
    this.hmsException = hmsException;
    switch (methodType) {
      case HMSActionResultListenerMethod.leave:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeTrackState:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeMetadata:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.endRoom:
        // TODO: Handle this case.
        print("HMSException ${hmsException.message}");
        break;
      case HMSActionResultListenerMethod.removePeer:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.acceptChangeRole:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeRole:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.changeTrackStateForRole:
        event = "Failed to Mute";
        break;
      case HMSActionResultListenerMethod.startRtmpOrRecording:
        break;
      case HMSActionResultListenerMethod.stopRtmpAndRecording:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.unknown:
        print("Unknown Method Called");
        break;
      case HMSActionResultListenerMethod.changeName:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.sendBroadcastMessage:
        // TODO: Handle this case.
        print("sendBroadcastMessage failure");
        break;
      case HMSActionResultListenerMethod.sendGroupMessage:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.sendDirectMessage:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.hlsStreamingStarted:
        // TODO: Handle this case.
        break;
      case HMSActionResultListenerMethod.hlsStreamingStopped:
        // TODO: Handle this case.
        break;

      case HMSActionResultListenerMethod.startScreenShare:
        break;

      case HMSActionResultListenerMethod.stopScreenShare:
        break;
    }
  }

  Future<List<HMSPeer>?> getPeers() async {
    return await _hmssdkInteractor.getPeers();
  }

  @override
  void onLocalAudioStats(
      {required HMSLocalAudioStats hmsLocalAudioStats,
      required HMSLocalAudioTrack track,
      required HMSPeer peer}) {}

  @override
  void onLocalVideoStats(
      {required HMSLocalVideoStats hmsLocalVideoStats,
      required HMSLocalVideoTrack track,
      required HMSPeer peer}) {}

  @override
  void onRemoteAudioStats(
      {required HMSRemoteAudioStats hmsRemoteAudioStats,
      required HMSRemoteAudioTrack track,
      required HMSPeer peer}) {}

  @override
  void onRemoteVideoStats(
      {required HMSRemoteVideoStats hmsRemoteVideoStats,
      required HMSRemoteVideoTrack track,
      required HMSPeer peer}) {}

  @override
  void onRTCStats({required HMSRTCStatsReport hmsrtcStatsReport}) {}
}
