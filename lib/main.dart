import 'package:flutter/material.dart';
import 'video_player_with_vast.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter VAST Video Player')),
        body: CustomVideoPlayer(
          videoUrl:
              'https://vz-6c38baf6-966.b-cdn.net/f6e6315e-e269-4993-a2dd-763cc6f39644/playlist.m3u8',
          vastEnabled: true,
          vastTagPreroll:
              'https://ayotising.com/fc.php?script=rmVideo&zoneid=59&format=vast3',
          vastTagMidroll:
              'https://ayotising.com/fc.php?script=rmVideo&zoneid=59&format=vast3',
          vastTagPostroll:
              'https://ayotising.com/fc.php?script=rmVideo&zoneid=59&format=vast3',
          midRollDuration: 30,
        ),
      ),
    );
  }
}
