import 'dart:convert';
import 'dart:io';

import 'request_elements/http_interaction.dart';

class Cassette {
  final String _filePath;
  final String name;
  bool _locked = false;

  // New field to store interactions
  List<HttpInteraction> _interactions = [];

  Cassette(folderPath, this.name) : _filePath = '$folderPath/$name.json';

  // New constructor to create a cassette from a JSON string
  Cassette.fromJson(String jsonData, this.name) : _filePath = '' {
    _createFromJson(jsonData);
  }

  int get numberOfInteractions =>
      _interactions.isNotEmpty ? _interactions.length : read().length;

  List<HttpInteraction> read() {
    // Return interactions if already loaded
    if (_interactions.isNotEmpty) {
      return _interactions;
    }

    if (!_exists()) {
      return [];
    }

    File file = File(_filePath);
    String fileContents = file.readAsStringSync();

    if (fileContents.isNotEmpty) {
      _interactions = jsonDecode(fileContents)
          .map<HttpInteraction>((e) => HttpInteraction.fromJson(e))
          .toList();
    }

    return _interactions;
  }

  void update(HttpInteraction interaction) {
    _preWriteCheck();
    _interactions.add(interaction);
    if (_filePath.isNotEmpty) {
      File file = File(_filePath);
      file.createSync(recursive: true);
      file.writeAsStringSync(
          jsonEncode(_interactions.map((e) => e.toJson()).toList()));
    }
  }

  void erase() {
    if (_filePath.isNotEmpty && File(_filePath).existsSync()) {
      File(_filePath).deleteSync();
    }
    _interactions.clear();
  }

  bool _exists() => _filePath.isNotEmpty && File(_filePath).existsSync();

  void lock() => _locked = true;
  void unlock() => _locked = false;
  void _preWriteCheck() {
    if (_locked) {
      throw Exception('Cassette $name is locked');
    }
  }

  void _createFromJson(String jsonData) {
    if (jsonData.isNotEmpty) {
      _interactions = jsonDecode(jsonData)
          .map<HttpInteraction>((e) => HttpInteraction.fromJson(e))
          .toList();
    }
  }
}
