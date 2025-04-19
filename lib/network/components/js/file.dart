/*
 * Copyright 2024 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';

/// FileBridge for file operation
/// @Author: Hongen Wang
class FileBridge {
  static const String code = '''
    function getApplicationSupportDirectory() {
      return sendMessage('getApplicationSupportDirectory', JSON.stringify(''));
    }
    
    function File(path) {
      return {
        path: path,
        readAsString: function() {
          return sendMessage('file.readAsString', JSON.stringify(this.path));
        },
        readAsStringSync: function() {
          return sendMessage('file.readAsStringSync', JSON.stringify(this.path));
        },
        readAsBytes: function() {
          return sendMessage('file.readAsBytes', JSON.stringify(this.path));
        },
        readAsBytesSync: function() {
          return sendMessage('file.readAsBytesSync', JSON.stringify(this.path));
        },
        writeAsString: function(content, append) {
          return sendMessage('file.writeAsString', JSON.stringify({path: this.path, content:content, append: append}));
        },
        writeAsStringSync: function(content, append) {
          return sendMessage('file.writeAsStringSync', JSON.stringify({path: this.path, content: content, append: append}));
        },
        writeAsBytes: function(bytes, append) {
          return sendMessage('file.writeAsBytes', JSON.stringify({path: this.path, bytes: bytes, append: append}));
        },
        writeAsBytesSync: function(bytes, append) {
          return sendMessage('file.writeAsBytesSync', JSON.stringify({path: this.path, bytes: bytes, append: append}));
        },
        length: function() {
          return sendMessage('file.length', JSON.stringify(this.path));
        },
        lengthSync: function() {
          return sendMessage('file.lengthSync', JSON.stringify(this.path));
        },
        delete: function() {
          return sendMessage('file.delete', JSON.stringify(this.path));
        },
        deleteSync: function() {
          return sendMessage('file.deleteSync', JSON.stringify(this.path));
        },        
        exists: function() {
          return sendMessage('file.exists', JSON.stringify(this.path));
        },
        existsSync: function() {
          return sendMessage('file.existsSync', JSON.stringify(this.path));
        },
        create: function(recursive, exclusive) {
          return sendMessage('file.create', JSON.stringify({path: this.path, recursive: recursive, exclusive: exclusive}));
        },
        createSync: function(recursive, exclusive) {
          return sendMessage('file.createSync', JSON.stringify({path: this.path, recursive: recursive, exclusive: exclusive}));
        },
        rename: function(newPath) {
          return sendMessage('file.rename', JSON.stringify(this.path, newPath));
        }
      };
    }
  ''';

  ///register file operation
  static void registerFile(JavascriptRuntime flutterJs) {
    var channels = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
    if (channels != null && channels.containsKey('file.readAsString')) {
      return;
    }
    var result = flutterJs.evaluate(code);
    if (result.isError) {
      logger.e('registerFile error: ${result.stringResult}');
    }

    flutterJs.onMessage('getApplicationSupportDirectory', (args) {
      return getApplicationSupportDirectory().then((dir) => dir.path);
    });

    flutterJs.onMessage('file.readAsString', (path) {
      return File(path).readAsString();
    });

    flutterJs.onMessage('file.readAsStringSync', (path) {
      var readAsStringSync = File(path).readAsStringSync();
      return readAsStringSync;
    });

    flutterJs.onMessage('file.readAsBytes', (path) {
      return File(path).readAsBytes();
    });

    flutterJs.onMessage('file.readAsBytesSync', (path) {
      return File(path).readAsBytesSync();
    });

    flutterJs.onMessage('file.writeAsString', (args) async {
      var path = args['path'];
      var content = args['content'];
      var append = args['append'] ?? false;
      await File(path).writeAsString(content, mode: append ? FileMode.append : FileMode.write);
    });

    flutterJs.onMessage('file.writeAsStringSync', (args) {
      var path = args['path'];
      var content = args['content'];
      var append = args['append'] ?? false;

      File(path).writeAsStringSync(content, mode: append ? FileMode.append : FileMode.write);
    });

    flutterJs.onMessage('file.writeAsBytes', (args) async {
      var path = args['path'];
      var bytes = List<int>.from(args['bytes']);
      var append = args['append'] ?? false;

      await File(path).writeAsBytes(bytes, mode: append ? FileMode.append : FileMode.write);
    });

    flutterJs.onMessage('file.writeAsBytesSync', (args) {
      var path = args['path'];
      var bytes = List<int>.from(args['bytes']);
      var append = args['append'] ?? false;

      File(path).writeAsBytesSync(bytes, mode: append ? FileMode.append : FileMode.write);
    });

    flutterJs.onMessage('file.length', (path) {
      return File(path).length();
    });

    flutterJs.onMessage('file.lengthSync', (path) {
      return File(path).lengthSync();
    });

    // flutterJs.onMessage('file.delete', (path) {
    //   return File(path).delete();
    // });
    //
    // flutterJs.onMessage('file.deleteSync', (path) {
    //   return File(path).deleteSync();
    // });

    flutterJs.onMessage('file.exists', (path) {
      return File(path).exists();
    });

    flutterJs.onMessage('file.existsSync', (path) {
      return File(path).existsSync();
    });

    flutterJs.onMessage('file.create', (args) {
      //bool recursive = false, bool exclusive = false
      var path = args['path'];
      var recursive = args['recursive'] ?? false;
      var exclusive = args['exclusive'] ?? false;
      File(path).create(recursive: recursive, exclusive: exclusive);
    });

    flutterJs.onMessage('file.createSync', (args) {
      var path = args['path'];
      var recursive = args['recursive'] ?? false;
      var exclusive = args['exclusive'] ?? false;
      File(path).createSync(recursive: recursive, exclusive: exclusive);
    });

    flutterJs.onMessage('file.rename', (args) async {
      var path = args['path'];
      var newPath = args['newPath'];
      await File(path).rename(newPath);
    });
  }
}
