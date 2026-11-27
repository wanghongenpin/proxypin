import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/content/body.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAgCAIAAABch4VNAAAADElEQVR4nGNgGFgAAACAAAH0EuoZAAAAAElFTkSuQmCC',
  );

  testWidgets('previews and saves a gzip PNG while preserving the captured bytes', (tester) async {
    final picker = _RecordingFilePicker();
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);

    final compressed = gzip.encode(png);
    final response = HttpResponse(HttpStatus.ok)..body = compressed;
    response.headers
      ..contentType = 'image/png'
      ..set('Content-Encoding', 'gzip');

    await tester.pumpWidget(_app(response));
    final image = find.byType(Image);
    for (var attempt = 0; attempt < 100 && image.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final provider = tester.widget<Image>(image).image as MemoryImage;
    expect(provider.bytes, png);
    await tester.runAsync(() => precacheImage(provider, tester.element(image)));
    await tester.pump();
    final rendered = find.descendant(of: image, matching: find.byType(RawImage));
    expect(tester.widget<RawImage>(rendered).image?.height, 32);

    await tester.tap(find.byTooltip('Save Image'));
    await tester.pump();
    expect(picker.savedBytes, png);
    expect(picker.fileName, endsWith('.png'));
    expect(response.body, same(compressed));
  });

  testWidgets('pending image decoding cannot replace a newer response', (tester) async {
    final first = _PendingImageResponse()..body = gzip.encode(png);
    first.headers
      ..contentType = 'image/png'
      ..set('Content-Encoding', 'gzip');
    final second = HttpResponse(HttpStatus.ok)
      ..body = png
      ..headers.contentType = 'image/png';

    await tester.pumpWidget(_app(first));
    final progress = find.byType(CircularProgressIndicator);
    for (var attempt = 0; attempt < 30 && progress.evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(progress, findsOneWidget);

    await tester.pumpWidget(_app(second));
    await tester.pump();
    first.decoded.complete(Uint8List(1));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, same(png));
    expect(progress, findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('decodes both deflate formats and preserves wire bytes', () async {
    final response = HttpResponse(HttpStatus.ok)..headers.set('Content-Encoding', 'deflate');
    for (final codec in [zlib, ZLibCodec(raw: true)]) {
      final compressed = codec.encode(png);
      response.body = compressed;
      expect(await response.decodeBodyBytes(), png);
      expect(response.body, same(compressed));
    }
  });
}

Widget _app(HttpResponse response) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: HttpBodyWidget(httpMessage: response, hideRequestRewrite: true)),
      ),
    );

class _PendingImageResponse extends HttpResponse {
  _PendingImageResponse() : super(HttpStatus.ok);

  final decoded = Completer<List<int>?>();

  @override
  Future<List<int>?> decodeBodyBytes() => decoded.future;
}

class _RecordingFilePicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  String? fileName;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.fileName = fileName;
    savedBytes = bytes;
    return null;
  }
}
