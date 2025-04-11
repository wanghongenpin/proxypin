import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_pickers/image_pickers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:zxing2/qrcode.dart' hide BarcodeFormat;
import 'package:image/image.dart' as img;

///@Author: Hongen Wang
/// qr code scanner
class QrCodeScanner {
  static Future<String?> scan(BuildContext context) async {
    var status = await Permission.camera.status;

    if (status.isRestricted || status.isPermanentlyDenied) {
      openAppSettings();
      return Future.value(null);
    } else if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (status.isDenied) {
      if (!context.mounted) return Future.value(null);
      AppLocalizations localizations = AppLocalizations.of(context)!;
      bool isCN = localizations.localeName == 'zh';
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                content: Text(isCN ? "请授予相机权限" : "Please grant camera permission"),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(localizations.confirm),
                  ),
                ],
              ));
      return Future.value(null);
    }

    if (!context.mounted) return Future.value(null);

    return await Navigator.of(context, rootNavigator: true)
        .push<String>(MaterialPageRoute(builder: (context) => QeCodeScanView()));
  }
}

class QeCodeScanView extends StatefulWidget {
  const QeCodeScanView({super.key});

  @override
  State<StatefulWidget> createState() {
    return _QrReaderViewState();
  }
}

class _QrReaderViewState extends State<QeCodeScanView> with TickerProviderStateMixin {
  final int animationTime = 2000;
  QRViewController? _controller;
  AnimationController? _animationController;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final QRCodeReader qrCodeReader = QRCodeReader();

  bool isScan = false;
  bool openFlashlight = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void _onCreateController(QRViewController controller) async {
    setState(() {
      _controller = controller;
    });
    startScan();
  }

  void startScan() async {
    isScan = true;

    _controller!.scannedDataStream.listen((scanData) async {
      await handle(scanData.code!);
    });

    _initAnimation();
  }

  handle(String data) async {
    if (!isScan) return;
    _controller?.stopCamera();
    stop();
    if (mounted) await Navigator.of(context, rootNavigator: true).maybePop(data);
  }

  void _initAnimation() {
    _animationController ??= AnimationController(vsync: this, duration: Duration(milliseconds: animationTime));
    _animationController
      ?..addListener(_upState)
      ..addStatusListener((state) {
        if (!mounted) {
          stop();
          return;
        }

        if (state == AnimationStatus.completed) {
          Future.delayed(Duration(seconds: 1), () {
            _animationController?.reverse();
          });
        } else if (state == AnimationStatus.dismissed) {
          Future.delayed(Duration(seconds: 1), () {
            _animationController?.forward();
          });
        }
      });

    _animationController?.forward();
  }

  void stop() {
    if (!isScan) {
      return;
    }

    isScan = false;
    _controller?.stopCamera();
    if (_animationController != null) {
      _animationController?.stop();
      _animationController?.dispose();
      _animationController = null;
    }
  }

  void _upState() {
    setState(() {});
  }

  setFlashlight() async {
    if (!isScan) return false;
    _controller?.toggleFlash();
    setState(() {
      openFlashlight = !openFlashlight;
    });
  }

  scanImage(String path) {
    stop();

    final bytes = File(path).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image != null) {
      final luminanceSource = RGBLuminanceSource(
          image.width,
          image.height,
          image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List()
      );

      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(luminanceSource));
      try {
        final decoded = qrCodeReader.decode(bitmap);
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(decoded.text);
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop("-1");
        }
      }
    } else {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop("-1");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.black,
        child: LayoutBuilder(builder: (context, constraints) {
          final qrScanSize = constraints.maxWidth * 0.85;
          final mediaQuery = MediaQuery.of(context);

          return Stack(
            children: <Widget>[
              SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: QRView(
                    key: qrKey,
                    formatsAllowed: [BarcodeFormat.qrcode],
                    overlay: QrScannerOverlayShape(
                      cutOutWidth: constraints.maxWidth,
                      cutOutHeight: constraints.maxHeight
                    ),
                    onQRViewCreated: _onCreateController,
                  )),
              Positioned(
                left: (constraints.maxWidth - qrScanSize) / 2,
                top: (constraints.maxHeight - qrScanSize) * 0.333333,
                child: CustomPaint(
                  painter: QrScanBoxPainter(
                    boxLineColor: Theme.of(context).colorScheme.primary,
                    animationValue: _animationController?.value ?? 0,
                    isForward: _animationController?.status == AnimationStatus.forward,
                  ),
                  child: SizedBox(width: qrScanSize, height: qrScanSize),
                ),
              ),
              Positioned(
                width: constraints.maxWidth,
                bottom: constraints.maxHeight == mediaQuery.size.height ? 12 + mediaQuery.padding.top : 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    IconButton(
                      onPressed: () {
                        ImagePickers.pickerPaths(showCamera: true).then((value) {
                          if (value.isNotEmpty) {
                            scanImage(value[0].path!);
                          }
                        });
                      },
                      icon: Icon(Icons.photo_library, color: Colors.white, size: 35),
                    ),
                    IconButton(
                      onPressed: setFlashlight,
                      icon: Icon(openFlashlight ? Icons.flash_on : Icons.flash_off, size: 35, color: Colors.white),
                    ),
                    TextButton(
                        onPressed: () {
                          stop();
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                        child: Text(localizations.cancel, style: TextStyle(color: Colors.white, fontSize: 18))),
                  ],
                ),
              )
            ],
          );
        }));
  }
}

class QrScanBoxPainter extends CustomPainter {
  final double animationValue;
  final bool isForward;
  final Color boxLineColor;

  QrScanBoxPainter({required this.animationValue, required this.isForward, required this.boxLineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final borderRadius = BorderRadius.all(Radius.circular(12)).toRRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawRRect(
      borderRadius,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    // leftTop
    path.moveTo(0, 50);
    path.lineTo(0, 12);
    path.quadraticBezierTo(0, 0, 12, 0);
    path.lineTo(50, 0);
    // rightTop
    path.moveTo(size.width - 50, 0);
    path.lineTo(size.width - 12, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 12);
    path.lineTo(size.width, 50);
    // rightBottom
    path.moveTo(size.width, size.height - 50);
    path.lineTo(size.width, size.height - 12);
    path.quadraticBezierTo(size.width, size.height, size.width - 12, size.height);
    path.lineTo(size.width - 50, size.height);
    // leftBottom
    path.moveTo(50, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, size.height - 50);

    canvas.drawPath(path, borderPaint);

    canvas.clipRRect(BorderRadius.all(Radius.circular(12)).toRRect(Offset.zero & size));

    // Draw a single horizontal line
    final linePaint = Paint()
      ..color = boxLineColor
      ..strokeWidth = 2.0;
    final lineY = size.height * animationValue;
    canvas.drawLine(
      Offset(0, lineY),
      Offset(size.width, lineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;

  @override
  bool shouldRebuildSemantics(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;
}
