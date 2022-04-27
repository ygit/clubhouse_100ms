import 'package:hmssdk_flutter/hmssdk_flutter.dart';
import 'package:mobx/mobx.dart';

@observable
class PeerTrackNode {
  HMSPeer peer;
  String name;
  bool isRaiseHand;
  @observable
  HMSTrack? audioTrack;
  PeerTrackNode(
      {required this.peer,
      this.name = "",
      this.audioTrack,
      this.isRaiseHand = false});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerTrackNode &&
          runtimeType == other.runtimeType &&
          peer.peerId == other.peer.peerId;

  @override
  String toString() {
    return 'PeerTracKNode{peerId: ${peer.peerId}, name: $name, track: $audioTrack}';
  }

  @override
  int get hashCode => peer.peerId.hashCode;
}
