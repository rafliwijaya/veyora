import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/measurement.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;
  final List<Measurement> _inMemoryList = [];

  DatabaseService._internal();

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    try {
      _database = await _initDatabase();
      return _database;
    } catch (e) {
      debugPrint('Database init error: $e');
      return null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'veyora_measurements.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        bpm REAL NOT NULL,
        rmssd REAL NOT NULL,
        sdnn REAL NOT NULL,
        pnn50 REAL NOT NULL,
        lf_hf_ratio REAL NOT NULL,
        stress_status TEXT NOT NULL,
        stress_confidence REAL NOT NULL,
        post_breathing INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<int> insertMeasurement(Measurement measurement) async {
    if (kIsWeb) {
      _inMemoryList.insert(0, measurement);
      return 1;
    }
    try {
      final db = await database;
      if (db == null) {
        _inMemoryList.insert(0, measurement);
        return 1;
      }
      return await db.insert(
        'measurements',
        measurement.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _inMemoryList.insert(0, measurement);
      return 1;
    }
  }

  Future<List<Measurement>> getAllMeasurements() async {
    if (kIsWeb) return List.unmodifiable(_inMemoryList);
    try {
      final db = await database;
      if (db == null) return List.unmodifiable(_inMemoryList);
      final result = await db.query(
        'measurements',
        orderBy: 'timestamp DESC',
      );
      return result.map((map) => Measurement.fromMap(map)).toList();
    } catch (e) {
      return List.unmodifiable(_inMemoryList);
    }
  }

  Future<Measurement?> getLatestMeasurement() async {
    if (kIsWeb) {
      return _inMemoryList.isNotEmpty ? _inMemoryList.first : null;
    }
    try {
      final db = await database;
      if (db == null) {
        return _inMemoryList.isNotEmpty ? _inMemoryList.first : null;
      }
      final result = await db.query(
        'measurements',
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (result.isNotEmpty) {
        return Measurement.fromMap(result.first);
      }
      return null;
    } catch (e) {
      return _inMemoryList.isNotEmpty ? _inMemoryList.first : null;
    }
  }

  Future<List<Measurement>> getRecentMeasurements({int limit = 14}) async {
    if (kIsWeb) {
      return _inMemoryList.take(limit).toList();
    }
    try {
      final db = await database;
      if (db == null) return _inMemoryList.take(limit).toList();
      final result = await db.query(
        'measurements',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return result.map((map) => Measurement.fromMap(map)).toList();
    } catch (e) {
      return _inMemoryList.take(limit).toList();
    }
  }

  Future<int> deleteMeasurement(int id) async {
    if (kIsWeb) {
      _inMemoryList.removeWhere((m) => m.id == id);
      return 1;
    }
    try {
      final db = await database;
      if (db == null) {
        _inMemoryList.removeWhere((m) => m.id == id);
        return 1;
      }
      return await db.delete(
        'measurements',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      _inMemoryList.removeWhere((m) => m.id == id);
      return 1;
    }
  }

  Future<int> clearAll() async {
    _inMemoryList.clear();
    if (kIsWeb) return 1;
    try {
      final db = await database;
      if (db == null) return 1;
      return await db.delete('measurements');
    } catch (e) {
      return 1;
    }
  }
}
