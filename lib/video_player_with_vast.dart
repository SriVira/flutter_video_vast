import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class CustomVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool vastEnabled;
  final String vastTagPreroll;
  final String vastTagMidroll;
  final String vastTagPostroll;
  final int midRollDuration;

  const CustomVideoPlayer({
    super.key,
    required this.videoUrl,
    this.vastEnabled = false, // VAST ads disabled by default
    required this.vastTagPreroll,
    required this.vastTagMidroll,
    required this.vastTagPostroll,
    this.midRollDuration = 30,
  });

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late VideoPlayerController _mainController;
  ChewieController? _chewieController; // Chewie controller for enhanced UI
  VideoPlayerController? _adController;
  bool _isPlayingAd = false;
  bool _isMidRollPlayed = false;
  bool _isMainControllerInitialized = false;
  bool _isAdControllerInitialized = false;
  bool _isSkipVisible = false;
  String? _adClickThroughUrl;
  int _skipTime = 5; // Number of seconds before "Skip Ad" is shown

  @override
  void initState() {
    super.initState();
    if (widget.vastEnabled) {
      playPrerollAd();
    } else {
      _initializeMainVideo();
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _adController?.dispose();
    _chewieController?.dispose(); // Dispose of Chewie controller
    super.dispose();
  }

  void _initializeMainVideo() {
    _mainController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          ..initialize().then((_) {
            if (mounted) {
              _createChewieController();
              setState(() {
                _isMainControllerInitialized = true;
              });
            }
            _mainController.play();
            _mainController.addListener(_checkMidRollAd);
            _mainController.addListener(_checkPostRollAd);
          });
  }

  // Initialize Chewie with the main controller
  void _createChewieController() {
    _chewieController = ChewieController(
      videoPlayerController: _mainController,
      autoPlay: true,
      looping: false,
      showControls: true,
      allowMuting: true,
      allowFullScreen: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Colors.red,
        handleColor: Colors.red,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.lightGreen,
      ),
      placeholder: Container(
        color: Colors.black,
      ),
    );
  }

  Future<void> playPrerollAd() async {
    final adUrl = await _getVastAd(widget.vastTagPreroll);
    if (adUrl != null) {
      playAd(adUrl, _initializeMainVideo);
    } else {
      _initializeMainVideo();
    }
  }

  Future<void> playMidrollAd() async {
    if (!_isMidRollPlayed && widget.vastEnabled) {
      final adUrl = await _getVastAd(widget.vastTagMidroll);
      if (adUrl != null) {
        _mainController.pause();
        _isMidRollPlayed = true;
        playAd(adUrl, () {
          _mainController.play();
        });
      }
    }
  }

  Future<void> playPostrollAd() async {
    final adUrl = await _getVastAd(widget.vastTagPostroll);
    if (adUrl != null) {
      _mainController.pause();
      playAd(adUrl, () {
        _mainController.play(); // Continue main video after postroll
      });
    }
  }

  Future<void> playAd(String adUrl, VoidCallback onAdComplete) async {
    if (_adController != null) {
      _adController!.dispose(); // Dispose previous ad controller if exists
    }

    _adController = VideoPlayerController.networkUrl(Uri.parse(adUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isAdControllerInitialized = true;
            _isPlayingAd = true;
            _startSkipTimer(); // Start skip ad countdown
          });
        }
        _adController!.play();
        _adController!.addListener(() {
          if (_adController!.value.position == _adController!.value.duration) {
            onAdComplete();
            _adController!.dispose();
            setState(() {
              _isAdControllerInitialized = false;
              _isPlayingAd = false;
            });
          }
        });
      });
  }

  Future<String?> _getVastAd(String vastUrl) async {
    try {
      final response = await http.get(Uri.parse(vastUrl));
      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final mediaFiles = document.findAllElements('MediaFile');
        final clickThrough = document.findAllElements('ClickThrough');

        final linearAd = document.findAllElements('Linear').first;

        // Fetch skipoffset attribute
        final skipOffset = linearAd.getAttribute('skipoffset');

        if (skipOffset != null) {
          _skipTime = _convertTimeToSeconds(skipOffset);
        }

        if (clickThrough.isNotEmpty) {
          _adClickThroughUrl = clickThrough.first.text.trim();
        }
        if (mediaFiles.isNotEmpty) {
          return mediaFiles.first.text.trim();
        }
      }
    } catch (e) {
      print('Error fetching VAST ad: $e');
    }
    return null;
  }

  int _convertTimeToSeconds(String time) {
    // Split time string by ":"
    final timeParts = time.split(':').map(int.parse).toList();

    // Calculate total seconds (HH:MM:SS)
    int hours = timeParts.length == 3 ? timeParts[0] : 0;
    int minutes = timeParts.length >= 2 ? timeParts[timeParts.length - 2] : 0;
    int seconds = timeParts.isNotEmpty ? timeParts[timeParts.length - 1] : 0;

    return hours * 3600 + minutes * 60 + seconds;
  }

  void _startSkipTimer() {
    Future.delayed(Duration(seconds: _skipTime), () {
      if (mounted) {
        setState(() {
          _isSkipVisible = true; // Show "Skip Ad" button after 5 seconds
        });
      }
    });
  }

  void _skipAd() {
    _initializeMainVideo();
    // Check if the ad controller is initialized before disposing
    if (_adController != null) {
      _adController!.dispose(); // Dispose the ad controller if it's initialized
      _adController = null; // Set it to null to avoid reuse
    }

    setState(() {
      _isSkipVisible = false; // Hide the skip button
      _isPlayingAd = false; // No longer playing an ad
      _isAdControllerInitialized = false;
    });

    // Ensure the main video controller resumes playing after skipping the ad
    if (_mainController.value.isInitialized) {
      _mainController.play();
    }
  }

  void _checkMidRollAd() {
    if (_mainController.value.position.inSeconds >= widget.midRollDuration &&
        !_isPlayingAd) {
      _isPlayingAd = true;
      playMidrollAd();
    }
  }

  void _checkPostRollAd() {
    if (_mainController.value.position == _mainController.value.duration) {
      playPostrollAd();
    }
  }

  Future<void> _onAdClick() async {
    try {
      if (_adClickThroughUrl != null) {
        await launchUrl(Uri.parse(_adClickThroughUrl!));
      } else {
        print('Could not launch the ad click-through URL');
      }
    } on Exception catch (e) {
      debugPrint("231->$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Center(
        child: _isMainControllerInitialized ||
                (_isAdControllerInitialized && _adController != null)
            ? Stack(
                children: [
                  AspectRatio(
                    aspectRatio: _isPlayingAd && _adController != null
                        ? _adController!.value.aspectRatio
                        : _mainController.value.aspectRatio,
                    child: _isPlayingAd && _adController != null
                        ? GestureDetector(
                            onTap: () async {
                              await _onAdClick();
                            },
                            child: VideoPlayer(_adController!))
                        : Chewie(controller: _chewieController!),
                  ),
                  if (_isSkipVisible && _isPlayingAd && _adController != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: ElevatedButton(
                        onPressed: _skipAd,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white.withOpacity(0.7),
                        ),
                        child: const Text('Skip Ad'),
                      ),
                    ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
