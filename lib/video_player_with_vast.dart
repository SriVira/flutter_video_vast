import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:url_launcher/url_launcher.dart';

class CustomVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool vastEnabled;
  final String vastTagPreroll;
  final String vastTagMidroll;
  final String vastTagPostroll;
  final int midRollDuration;

  CustomVideoPlayer({
    required this.videoUrl,
    this.vastEnabled = false, // VAST ads disabled by default
    required this.vastTagPreroll,
    required this.vastTagMidroll,
    required this.vastTagPostroll,
    this.midRollDuration = 0,
  });

  @override
  _CustomVideoPlayerState createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late VideoPlayerController _mainController;
  VideoPlayerController? _adController;
  bool _isPlayingAd = false;
  bool _isMidRollPlayed = false;
  bool _isMainControllerInitialized = false;
  bool _isAdControllerInitialized = false;
  bool _isControlsVisible = false;
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
    super.dispose();
  }

  void _initializeMainVideo() {
    _mainController = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isMainControllerInitialized = true;
          });
        }
        _mainController.play();
        _mainController.addListener(_checkMidRollAd);
        _mainController.addListener(_checkPostRollAd);
      });
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
        print('Postroll ad finished');
        _mainController.play(); // Continue main video after postroll
      });
    }
  }

  Future<void> playAd(String adUrl, VoidCallback onAdComplete) async {
    if (_adController != null) {
      _adController!.dispose(); // Dispose previous ad controller if exists
    }

    _adController = VideoPlayerController.network(adUrl)
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
          if (_adController!.value.hasError) {
            print("Ad player error: ${_adController!.value.errorDescription}");
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
    // Skip the ad and continue the main video
    if (_adController != null) {
      _adController!
          .dispose(); // Dispose the ad controller after skipping the ad
      _adController = null; // Set it to null to avoid reuse
      setState(() {
        _isSkipVisible = false; // Hide the skip button
        _isPlayingAd = false; // No longer playing an ad
        _isAdControllerInitialized = false;
      });
      _mainController.play(); // Resume main video after skipping the ad
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

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  void _onAdClick() async {
    if (_adClickThroughUrl != null && await canLaunch(_adClickThroughUrl!)) {
      await launch(_adClickThroughUrl!,
          forceSafariVC: false, forceWebView: false);
    } else {
      print('Could not launch the ad click-through URL');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleControls,
      child: Center(
        child: _isMainControllerInitialized || _isAdControllerInitialized
            ? Stack(
                children: [
                  AspectRatio(
                    aspectRatio: _isPlayingAd
                        ? _adController!.value.aspectRatio
                        : _mainController.value.aspectRatio,
                    child: GestureDetector(
                      onTap:
                          _isPlayingAd ? _onAdClick : null, // Handle ad click
                      child: VideoPlayer(
                          _isPlayingAd ? _adController! : _mainController),
                    ),
                  ),
                  if (_isSkipVisible && _isPlayingAd)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: ElevatedButton(
                        onPressed: _skipAd,
                        style: ElevatedButton.styleFrom(
                          primary: Colors.white
                              .withOpacity(0.7), // Transparent white
                          onPrimary: Colors.black, // Text color
                        ),
                        child: Text('Skip Ad'),
                      ),
                    ),
                  if (_isControlsVisible) ...[
                    _buildControlsOverlay(),
                  ],
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: VideoProgressIndicator(
                      _isPlayingAd ? _adController! : _mainController,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: Colors.red,
                        backgroundColor: Colors.grey.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
              )
            : CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              _isPlayingAd
                  ? _adController!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow
                  : _mainController.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
              color: Colors.white,
              size: 48.0,
            ),
            onPressed: () {
              setState(() {
                if (_isPlayingAd) {
                  _adController!.value.isPlaying
                      ? _adController!.pause()
                      : _adController!.play();
                } else {
                  _mainController.value.isPlaying
                      ? _mainController.pause()
                      : _mainController.play();
                }
              });
            },
          ),
        ],
      ),
    );
  }
}
