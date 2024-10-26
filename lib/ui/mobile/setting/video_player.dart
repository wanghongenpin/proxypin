// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:video_player/video_player.dart';
//
// void main() => runApp(const VideoPlayerApp());
//
// class VideoPlayerApp extends StatelessWidget {
//   const VideoPlayerApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return const MaterialApp(
//       title: 'Video Player Demo',
//       home: VideoPlayerScreen(),
//     );
//   }
// }
//
// class VideoPlayerScreen extends StatefulWidget {
//   const VideoPlayerScreen({super.key});
//
//   @override
//   State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
// }
//
// class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
//   late VideoPlayerController _controller;
//   late Future<void> _initializeVideoPlayerFuture;
//
//   @override
//   void initState() {
//     super.initState();
//
//     _controller = VideoPlayerController.network(
//       'https://github.com/wanghongenpin/proxypin/assets/24794200/38bc5a83-999f-4af2-9d74-863532a81cef',
//       videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: true),
//     );
//     _initializeVideoPlayerFuture = _controller.initialize();
//     _initializeVideoPlayerFuture.whenComplete(() {
//       final MediaQueryData data = MediaQuery.of(context);
//
//       EdgeInsets paddingSafeArea = data.padding;
//       double widthScreen = data.size.width;
//       _controller.setPictureInPictureOverlayRect(
//           rect: Rect.fromLTWH(0, paddingSafeArea.top, widthScreen, 9 * widthScreen / 16));
//       // _controller.setAutomaticallyStartPictureInPicture(enableStartPictureInPictureAutomaticallyFromInline: true);
//     });
//     _controller.addListener(() {
//       setState(() {});
//     });
//   }
//
//   @override
//   void dispose() {
//     // Ensure disposing of the VideoPlayerController to free up resources.
//     _controller.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return FutureBuilder(
//       future: _initializeVideoPlayerFuture,
//       builder: (context, snapshot) {
//         if (snapshot.connectionState == ConnectionState.done) {
//           return AspectRatio(
//             aspectRatio: _controller.value.aspectRatio,
//             // Use the VideoPlayer widget to display the video.
//             child: Stack(alignment: Alignment.bottomCenter, children: [
//               VideoPlayer(_controller),
//               _ControlsOverlay(controller: _controller),
//               VideoProgressIndicator(
//                 _controller,
//                 allowScrubbing: true,
//               ),
//             ]),
//           );
//         } else {
//           // If the VideoPlayerController is still initializing, show a
//           // loading spinner.
//           return const Center(
//             child: CircularProgressIndicator(),
//           );
//         }
//       },
//     );
//   }
// }
//
// class _ControlsOverlay extends StatelessWidget {
//   const _ControlsOverlay({required this.controller});
//
//   static const List<double> _playbackRates = <double>[
//     0.25,
//     0.5,
//     1.0,
//     1.5,
//     2.0,
//   ];
//
//   final VideoPlayerController controller;
//
//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       children: <Widget>[
//         AnimatedSwitcher(
//           duration: const Duration(milliseconds: 50),
//           reverseDuration: const Duration(milliseconds: 200),
//           child: controller.value.isPlaying
//               ? const SizedBox.shrink()
//               : Container(
//                   color: Colors.black26,
//                   child: const Center(
//                     child: Icon(
//                       Icons.play_arrow,
//                       color: Colors.white,
//                       size: 80.0,
//                       semanticLabel: 'Play',
//                     ),
//                   ),
//                 ),
//         ),
//         GestureDetector(
//           onTap: () {
//             controller.value.isPlaying ? controller.pause() : controller.play();
//           },
//         ),
//         Align(
//             alignment: Alignment.topRight,
//             child: IconButton(
//               onPressed: () async {
//                 controller.startPictureInPicture();
//               },
//               icon: const Icon(Icons.picture_in_picture),
//             )),
//         Align(
//           alignment: Alignment.bottomRight,
//           child: PopupMenuButton<double>(
//             initialValue: controller.value.playbackSpeed,
//             tooltip: 'Playback speed',
//             onSelected: (double speed) {
//               controller.setPlaybackSpeed(speed);
//             },
//             itemBuilder: (BuildContext context) {
//               return <PopupMenuItem<double>>[
//                 for (final double speed in _playbackRates)
//                   PopupMenuItem<double>(
//                     value: speed,
//                     child: Text('${speed}x'),
//                   )
//               ];
//             },
//             child: Padding(
//               padding: const EdgeInsets.symmetric(
//                 vertical: 15,
//                 horizontal: 16,
//               ),
//               child: Text('${controller.value.playbackSpeed}x', style: const TextStyle(color: Colors.white)),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }
