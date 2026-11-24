import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Book {
  Book({
    required this.id,
    required this.title,
    required this.path,
    required this.addedAt,
    this.lastPage = 1,
    this.pageCount = 0,
    this.lastOpenedAt,
  });

  final String id;
  String title;
  final String path;
  final DateTime addedAt;
  int lastPage;
  int pageCount;
  DateTime? lastOpenedAt;

  double get progress => pageCount <= 0 ? 0 : (lastPage / pageCount).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'addedAt': addedAt.toIso8601String(),
        'lastPage': lastPage,
        'pageCount': pageCount,
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        path: j['path'] as String,
        addedAt: DateTime.parse(j['addedAt'] as String),
        lastPage: (j['lastPage'] as int?) ?? 1,
        pageCount: (j['pageCount'] as int?) ?? 0,
        lastOpenedAt: j['lastOpenedAt'] == null ? null : DateTime.parse(j['lastOpenedAt'] as String),
      );
}

/// Biblioteca local: los PDF se copian al almacenamiento privado de la app.
class LibraryService extends ChangeNotifier {
  LibraryService._();
  static final LibraryService instance = LibraryService._();

  final List<Book> _books = [];
  List<Book> get books {
    final list = [..._books];
    list.sort((a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(a.lastOpenedAt ?? a.addedAt));
    return list;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('books');
    _books.clear();
    if (raw != null) {
      for (final j in jsonDecode(raw) as List) {
        final b = Book.fromJson(j as Map<String, dynamic>);
        if (File(b.path).existsSync()) _books.add(b);
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('books', jsonEncode(_books.map((b) => b.toJson()).toList()));
    notifyListeners();
  }

  Future<Book> importFile(String sourcePath, {String? name}) async {
    final dir = await getApplicationDocumentsDirectory();
    final booksDir = Directory(p.join(dir.path, 'books'));
    await booksDir.create(recursive: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final dest = p.join(booksDir.path, '$id.pdf');
    await File(sourcePath).copy(dest);
    final title = p.basenameWithoutExtension(name ?? sourcePath).replaceAll('_', ' ');
    final book = Book(id: id, title: title, path: dest, addedAt: DateTime.now());
    _books.add(book);
    await _save();
    return book;
  }

  Future<void> updateProgress(Book book, {required int page, int? pageCount}) async {
    book.lastPage = page;
    if (pageCount != null) book.pageCount = pageCount;
    book.lastOpenedAt = DateTime.now();
    await _save();
  }

  Future<void> rename(Book book, String title) async {
    book.title = title;
    await _save();
  }

  Future<void> remove(Book book) async {
    _books.removeWhere((b) => b.id == book.id);
    try {
      await File(book.path).delete();
    } catch (_) {}
    await _save();
  }
}
