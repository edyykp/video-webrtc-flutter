import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoSession {
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  MediaStream? localStream;

  Future<void> initRenderers() async {
    await localRenderer.initialize();
  }

  Future<void> openUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': {
        'facingMode': 'user', // Camera frontală
      },
    };

    localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localRenderer.srcObject = localStream;
  }
}
