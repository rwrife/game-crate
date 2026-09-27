import Foundation
import GRDB

/// Version one is immutable. Add a new migration for future schema changes.
public enum CrateStoreSchema {
    public static let migrationIdentifiers = ["v1"]
    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE games (
                  id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL,
                  minimum_players INTEGER, maximum_players INTEGER,
                  play_time_minutes INTEGER, categories_json TEXT NOT NULL,
                  created_at REAL, notes TEXT
                );
                CREATE TABLE people (
                  id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL,
                  created_at REAL, notes TEXT
                );
                CREATE TABLE plays (
                  id TEXT PRIMARY KEY NOT NULL,
                  game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
                  occurred_at REAL, notes TEXT,
                  correction_of TEXT REFERENCES plays(id) ON DELETE CASCADE
                );
                CREATE TABLE play_players (
                  play_id TEXT NOT NULL REFERENCES plays(id) ON DELETE CASCADE,
                  person_id TEXT NOT NULL REFERENCES people(id) ON DELETE CASCADE,
                  rating INTEGER CHECK (rating BETWEEN 1 AND 5), notes TEXT,
                  PRIMARY KEY (play_id, person_id)
                );
                CREATE INDEX plays_occurred_at ON plays(occurred_at);
                CREATE INDEX plays_game_id ON plays(game_id);
                CREATE INDEX play_players_person_id ON play_players(person_id);
                CREATE TRIGGER plays_no_update BEFORE UPDATE ON plays
                BEGIN SELECT RAISE(ABORT, 'plays are append-only'); END;
                CREATE TRIGGER play_players_no_update BEFORE UPDATE ON play_players
                BEGIN SELECT RAISE(ABORT, 'play ratings are append-only'); END;
                -- Direct DELETE of ledger rows is forbidden: history is
                -- append-only and corrections are compensating events, never
                -- erasures. The WHEN guards let foreign-key CASCADE through:
                -- deleting a game (parent row already gone) removes its plays,
                -- and deleting a person or game removes the participant ratings
                -- they touched. A caller deleting a play or rating row directly,
                -- while its game and person still exist, is rejected.
                CREATE TRIGGER plays_no_direct_delete BEFORE DELETE ON plays
                WHEN EXISTS(SELECT 1 FROM games WHERE id = OLD.game_id)
                BEGIN SELECT RAISE(ABORT, 'plays are append-only; delete the game to remove its history'); END;
                CREATE TRIGGER play_players_no_direct_delete BEFORE DELETE ON play_players
                WHEN EXISTS(SELECT 1 FROM plays WHERE id = OLD.play_id)
                 AND EXISTS(SELECT 1 FROM people WHERE id = OLD.person_id)
                BEGIN SELECT RAISE(ABORT, 'play ratings are append-only; delete the person or game instead'); END;
                """)
        }
        return migrator
    }()
}

public struct CrateStore: Sendable {
    public let db: any DatabaseWriter

    public init(db: any DatabaseWriter) throws {
        try CrateStoreSchema.migrator.migrate(db)
        self.db = db
    }

    public static func inMemory() throws -> CrateStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try CrateStore(db: DatabaseQueue(configuration: configuration))
    }

    public static func atPath(_ path: String) throws -> CrateStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try CrateStore(db: DatabaseQueue(path: path, configuration: configuration))
    }
}
