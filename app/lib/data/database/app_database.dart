import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'ottawa_swim_finder.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE facilities (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        postal_code TEXT,
        latitude REAL,
        longitude REAL,
        region TEXT,
        url TEXT,
        content_hash TEXT,
        last_updated INTEGER,
        has_pool INTEGER DEFAULT 1,
        metadata_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        facility_id TEXT NOT NULL,
        category TEXT NOT NULL,
        raw_category TEXT,
        schedule_type TEXT NOT NULL,
        day_of_week INTEGER,
        date TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        notes TEXT,
        date_range_start TEXT,
        date_range_end TEXT,
        last_updated INTEGER,
        FOREIGN KEY (facility_id) REFERENCES facilities(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE favorites (
        facility_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (facility_id) REFERENCES facilities(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE scrape_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        facility_id TEXT,
        status TEXT NOT NULL,
        message TEXT,
        html_snapshot_path TEXT,
        content_hash TEXT,
        duration_ms INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_schedules_facility_date ON schedules(facility_id, date)');
    await db.execute(
        'CREATE INDEX idx_schedules_category_date ON schedules(category, date)');
    await db.execute(
        'CREATE INDEX idx_schedules_time ON schedules(date, start_time, end_time)');
    await db.execute('CREATE INDEX idx_facilities_region ON facilities(region)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
