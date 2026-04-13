import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_consultation/managers/video_call_manager.dart';

void main() {
  runApp(const TelemedicineApp());
}

class TelemedicineApp extends StatelessWidget {
  const TelemedicineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telemedicină - Consultație Video',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _serverController = TextEditingController(
    text:
        'http://10.0.2.2:3000', // Use emulator host loopback for Android emulator
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telemedicină - Consultație Video'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medical_services, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Consultație Video Criptată P2P',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Camera: camera_101',
              style: TextStyle(fontSize: 18, color: Color(0xFF757575)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://10.0.2.2:3000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                if (_serverController.text.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VideoCallPage(serverUrl: _serverController.text),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Completați adresa serverului'),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 15,
                ),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Începe Consultația'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }
}

class VideoCallPage extends StatefulWidget {
  final String serverUrl;

  const VideoCallPage({super.key, required this.serverUrl});

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  late VideoCallManager _callManager;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _callManager = VideoCallManager();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      // Initialize renderers
      await _callManager.initRenderers();

      // Initialize socket
      await _callManager.initSocket(widget.serverUrl);

      // Open camera and microphone
      await _callManager.openUserMedia();

      // Create peer connection
      await _callManager.createPeerConnectionInstance();

      // Set up callbacks
      _callManager.onCallStateChanged = (state) {
        setState(() {});
      };

      _callManager.onError = (error) {
        setState(() {
          _errorMessage = error;
        });
      };

      _callManager.onRemoteStreamAdded = () {
        setState(() {});
      };

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Eroare la inițializare: $e';
      });
    }
  }

  Future<void> _startCall() async {
    try {
      await _callManager.makeCall();
    } catch (e) {
      setState(() {
        _errorMessage = 'Eroare la pornirea apelului: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inițializare...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eroare')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Înapoi'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera: camera_101'),
        actions: [
          if (_callManager.isConnected)
            const Icon(Icons.security, color: Colors.green),
        ],
      ),
      body: Stack(
        children: [
          // Remote video (full screen)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _callManager.remoteRenderer.srcObject != null
                  ? RTCVideoView(
                      _callManager.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : const Center(
                      child: Text(
                        'Așteptând pacientul...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
            ),
          ),

          // Local video (picture-in-picture)
          Positioned(
            right: 20,
            bottom: 120,
            child: Container(
              width: 120,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
              clipBehavior: Clip.hardEdge,
              child: RTCVideoView(
                _callManager.localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

          // Connection status overlay
          if (_callManager.callState == CallState.connecting)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Conectare...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Control bar
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mute button
                FloatingActionButton(
                  backgroundColor: _callManager.isMuted
                      ? Colors.red
                      : Colors.white,
                  onPressed: () async {
                    await _callManager.toggleMute();
                    if (mounted) setState(() {});
                  },
                  child: Icon(
                    _callManager.isMuted ? Icons.mic_off : Icons.mic,
                    color: _callManager.isMuted ? Colors.white : Colors.blue,
                  ),
                ),
                const SizedBox(width: 20),

                // Start/End call button
                if (_callManager.callState == CallState.idle)
                  FloatingActionButton(
                    backgroundColor: Colors.green,
                    onPressed: _startCall,
                    child: const Icon(Icons.call),
                  )
                else
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () async {
                      await _callManager.hangUp();
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Icon(Icons.call_end),
                  ),

                const SizedBox(width: 20),

                // Switch camera button
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () => _callManager.switchCamera(),
                  child: const Icon(Icons.switch_camera, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _callManager.dispose();
    super.dispose();
  }
}
