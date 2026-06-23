import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'ottawa_swim_finder.db';
  static const _dbVersion = 9;

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
        last_successful_sync_at INTEGER,
        sync_status TEXT DEFAULT 'OK',
        has_pool INTEGER DEFAULT 1,
        facility_type TEXT DEFAULT 'INDOOR_POOL',
        data_model TEXT DEFAULT 'SWIM_SCHEDULE',
        display_status TEXT DEFAULT 'LIVE_OK',
        schedule_mode TEXT DEFAULT 'HAS_SWIM_SCHEDULE',
        schedule_trust_status TEXT DEFAULT 'UNVERIFIED',
        schedule_source TEXT DEFAULT 'none',
        schedule_verified_at INTEGER,
        fixture_generated_at INTEGER,
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
      CREATE TABLE sync_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        status TEXT NOT NULL,
        success_rate REAL,
        facilities_total INTEGER DEFAULT 0,
        facilities_updated INTEGER DEFAULT 0,
        facilities_skipped INTEGER DEFAULT 0,
        facilities_blocked INTEGER DEFAULT 0,
        facilities_failed INTEGER DEFAULT 0,
        facilities_stale INTEGER DEFAULT 0,
        schedule_count_before INTEGER DEFAULT 0,
        schedule_count_after INTEGER DEFAULT 0,
        message TEXT,
        anti_corruption_triggered INTEGER DEFAULT 0
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
    await db.execute(
        'CREATE INDEX idx_facilities_type ON facilities(facility_type)');

    await _createSavedSwimsTable(db);
    await _createFacilityInteractionsTable(db);
    await _createHabitEventsTable(db);
  }

  Future<void> _createHabitEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE habit_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        facility_id TEXT NOT NULL,
        recorded_at INTEGER NOT NULL,
        action_type TEXT NOT NULL,
        weight REAL NOT NULL,
        day_of_week INTEGER NOT NULL,
        hour_of_day INTEGER NOT NULL,
        time_bucket TEXT NOT NULL,
        swim_start_time TEXT,
        FOREIGN KEY (facility_id) REFERENCES facilities(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_habit_events_recorded ON habit_events(recorded_at)',
    );
    await db.execute(
      'CREATE INDEX idx_habit_events_facility ON habit_events(facility_id, recorded_at)',
    );
  }

  Future<void> _createFacilityInteractionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE facility_interactions (
        facility_id TEXT PRIMARY KEY,
        view_count INTEGER NOT NULL DEFAULT 0,
        last_viewed_at INTEGER,
        saved_count INTEGER NOT NULL DEFAULT 0,
        swim_detail_clicks INTEGER NOT NULL DEFAULT 0,
        impression_count INTEGER NOT NULL DEFAULT 0,
        ignore_count INTEGER NOT NULL DEFAULT 0,
        last_ignored_at INTEGER,
        FOREIGN KEY (facility_id) REFERENCES facilities(id)
      )
    ''');
  }

  Future<void> _createSavedSwimsTable(Database db) async {
    await db.execute('''
      CREATE TABLE saved_swims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id INTEGER,
        facility_id TEXT NOT NULL,
        category TEXT NOT NULL,
        raw_category TEXT,
        date TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        reminder_minutes INTEGER,
        is_recurring INTEGER NOT NULL DEFAULT 0,
        day_of_week INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (facility_id) REFERENCES facilities(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_saved_swims_date ON saved_swims(date, start_time)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSavedSwimsTable(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE saved_swims ADD COLUMN is_recurring INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE saved_swims ADD COLUMN day_of_week INTEGER',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE facilities ADD COLUMN last_successful_sync_at INTEGER',
      );
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN sync_status TEXT DEFAULT 'OK'",
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at INTEGER NOT NULL,
          completed_at INTEGER,
          status TEXT NOT NULL,
          success_rate REAL,
          facilities_total INTEGER DEFAULT 0,
          facilities_updated INTEGER DEFAULT 0,
          facilities_skipped INTEGER DEFAULT 0,
          facilities_blocked INTEGER DEFAULT 0,
          facilities_failed INTEGER DEFAULT 0,
          facilities_stale INTEGER DEFAULT 0,
          schedule_count_before INTEGER DEFAULT 0,
          schedule_count_after INTEGER DEFAULT 0,
          message TEXT,
          anti_corruption_triggered INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN facility_type TEXT DEFAULT 'INDOOR_POOL'",
      );
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN schedule_mode TEXT DEFAULT 'HAS_SWIM_SCHEDULE'",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_facilities_type ON facilities(facility_type)',
      );
    }
    if (oldVersion < 6) {
      await _createFacilityInteractionsTable(db);
    }
    if (oldVersion < 7) {
      await _createHabitEventsTable(db);
    }
    if (oldVersion < 8) {
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN schedule_trust_status TEXT DEFAULT 'UNVERIFIED'",
      );
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN schedule_source TEXT DEFAULT 'none'",
      );
      await db.execute(
        'ALTER TABLE facilities ADD COLUMN schedule_verified_at INTEGER',
      );
      await db.execute(
        'ALTER TABLE facilities ADD COLUMN fixture_generated_at INTEGER',
      );
    }
    if (oldVersion < 9) {
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN data_model TEXT DEFAULT 'SWIM_SCHEDULE'",
      );
      await db.execute(
        "ALTER TABLE facilities ADD COLUMN display_status TEXT DEFAULT 'LIVE_OK'",
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
