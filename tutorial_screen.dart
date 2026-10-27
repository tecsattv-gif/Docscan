import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Vídeo "Como usar" (assets/video/tutorial.mp4). Toque para pausar/continuar.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});
  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _c = VideoPlayerController.asset('assets/video/tutorial.mp4');
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    final v = _c.value;
    if (v.isPlaying) {
      _c.pause();
    } else {
      if (v.position >= v.duration) _c.seekTo(Duration.zero);
      _c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final ended = v.isInitialized && !v.isPlaying && v.position >= v.duration;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Como usar'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: _error
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Não foi possível abrir o vídeo.',
                          style: TextStyle(color: Colors.white)),
                    )
                  : !v.isInitialized
                      ? Image.asset('assets/video/capa.jpg')
                      : GestureDetector(
                          onTap: _toggle,
                          child: AspectRatio(
                            aspectRatio: v.aspectRatio,
                            child: Stack(alignment: Alignment.center, children: [
                              VideoPlayer(_c),
                              if (!v.isPlaying)
                                CircleAvatar(
                                  radius: 34,
                                  backgroundColor: Colors.black54,
                                  child: Icon(
                                      ended ? Icons.replay : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 40),
                                ),
                            ]),
                          ),
                        ),
            ),
          ),
          if (v.isInitialized)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: VideoProgressIndicator(_c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                      playedColor: Color(0xFF19B394),
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12)),
            ),
        ]),
      ),
    );
  }
}
