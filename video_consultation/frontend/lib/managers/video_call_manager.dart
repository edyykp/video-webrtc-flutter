// ignore_for_file: avoid_print

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

enum CallState { idle, connecting, connected, failed, disconnected }

class VideoCallManager {
  // WebRTC Components
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  MediaStream? _localStream;

  // Socket.io
  io.Socket? _socket;

  // State tracking
  CallState _callState = CallState.idle;
  bool _isMuted = false;
  bool _isCameraSwitched = false;

  // Callbacks
  Function(CallState)? onCallStateChanged;
  Function(String)? onError;
  Function()? onRemoteStreamAdded;
  Function()? onRemoteStreamRemoved;

  // STUN configuration
  final Map<String, dynamic> _configuration = {
    "iceServers": [
      {"url": "stun:stun.l.google.com:19302"},
      {"url": "stun:stun1.l.google.com:19302"},
      {"url": "stun:stun2.l.google.com:19302"},
    ],
    "sdpSemantics": "unified-plan",
  };

  // Initialize renderers
  Future<void> initRenderers() async {
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
    } catch (e) {
      _handleError("Error initializing renderers: $e");
    }
  }

  // Initialize socket connection
  Future<void> initSocket(String serverUrl) async {
    try {
      _socket = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

      _socket!.on('connect', (_) {
        print('[SOCKET] Conectat la server');
        _socket?.emit('join');
      });

      _socket!.on('connect_error', (error) {
        print('[SOCKET] Eroare conectare: $error');
        _handleError('Socket connect error: $error');
      });

      _socket!.on('ready', (_) {
        print('[SOCKET] Ready received - peer is present');
        if (_callState == CallState.idle) {
          makeCall();
        }
      });

      _socket!.on('message', (data) {
        print('[SOCKET] Mesaj primit: ${data['type']}');
        _handleIncomingMessage(data);
      });

      _socket!.on('disconnect', (_) {
        print('[SOCKET] Deconectat de la server');
        _setCallState(CallState.disconnected);
      });

      _socket!.connect();
    } catch (e) {
      _handleError("Error initializing socket: $e");
    }
  }

  // Open camera and microphone
  Future<void> openUserMedia() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;
      print('[MEDIA] Stream media capturat cu succes');
    } catch (e) {
      _handleError("Error accessing camera: $e");
    }
  }

  // Create peer connection
  Future<void> createPeerConnectionInstance() async {
    try {
      _peerConnection = await createPeerConnection(_configuration);

      // Add local tracks
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      // Handle remote tracks
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('[WEBRTC] Track primit: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams[0];
          onRemoteStreamAdded?.call();
        }
      };

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _socket?.emit('message', {
          'payload': {'type': 'candidate', 'candidate': candidate.toMap()},
        });
      };

      // Monitor connection state
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('[WEBRTC] Stare conexiune: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _setCallState(CallState.connected);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _setCallState(CallState.disconnected);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _setCallState(CallState.failed);
        }
      };

      print('[WEBRTC] PeerConnection creat cu succes');
    } catch (e) {
      _handleError("Error creating PeerConnection: $e");
    }
  }

  // Make call (Initiator)
  Future<void> makeCall() async {
    try {
      if (_callState == CallState.connected) {
        print('[WEBRTC] makeCall skipped because already connected');
        return;
      }

      _setCallState(CallState.connecting);

      // Create offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _socket?.emit('message', {
        'payload': {'type': offer.type, 'sdp': offer.sdp},
      });

      print('[WEBRTC] Ofertă trimisă');
    } catch (e) {
      _handleError("Error making call: $e");
    }
  }

  // Handle incoming messages from socket
  void _handleIncomingMessage(Map<String, dynamic> data) async {
    try {
      final type = data['type'];
      final sdp = data['sdp'];
      final candidate = data['candidate'];

      if (type == 'offer') {
        // Receiver side
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, type),
        );

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        _socket?.emit('message', {
          'payload': {'type': answer.type, 'sdp': answer.sdp},
        });

        print('[WEBRTC] Răspuns trimis');
      } else if (type == 'answer') {
        // Initiator side
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(sdp, type),
        );

        print('[WEBRTC] Răspuns primit');
      } else if (type == 'candidate') {
        // ICE candidate
        RTCIceCandidate iceCandidate = RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        );

        await _peerConnection!.addCandidate(iceCandidate);
        print('[ICE] Candidat adăugat');
      }
    } catch (e) {
      _handleError("Error handling message: $e");
    }
  }

  // Mute/Unmute audio
  Future<void> toggleMute() async {
    try {
      if (_localStream != null) {
        _isMuted = !_isMuted;
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = !_isMuted;
        }
        print('[MEDIA] Microfon ${_isMuted ? 'oprit' : 'pornit'}');
      }
    } catch (e) {
      _handleError("Error toggling mute: $e");
    }
  }

  // Switch camera
  Future<void> switchCamera() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getVideoTracks()) {
          await Helper.switchCamera(track);
        }
        _isCameraSwitched = !_isCameraSwitched;
        print('[MEDIA] Cameră schimbată');
      }
    } catch (e) {
      _handleError("Error switching camera: $e");
    }
  }

  // Hang up call
  Future<void> hangUp() async {
    try {
      // Stop all tracks
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Disconnect socket
      _socket?.disconnect();

      _setCallState(CallState.idle);
      _isMuted = false;
      _isCameraSwitched = false;

      print('[WEBRTC] Apel terminat');
    } catch (e) {
      _handleError("Error hanging up: $e");
    }
  }

  // Set call state and notify listeners
  void _setCallState(CallState state) {
    _callState = state;
    onCallStateChanged?.call(state);
  }

  // Handle errors
  void _handleError(String error) {
    print('[ERROR] $error');
    onError?.call(error);
  }

  // Getters
  CallState get callState => _callState;
  bool get isMuted => _isMuted;
  bool get isCameraSwitched => _isCameraSwitched;
  bool get isConnected => _callState == CallState.connected;

  // Cleanup
  Future<void> dispose() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      await _peerConnection?.close();
      _socket?.disconnect();
    } catch (e) {
      print('[ERROR] Error disposing: $e');
    }
  }
}
