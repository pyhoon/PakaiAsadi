-- Pakai Asadi M2 fixture.
-- Apply only to a disposable SQLite database, for example the demo-created
-- source/data/demo.db. Re-running this script replaces these fixture objects.
--   sqlite3 source/data/demo.db ".read tests/M2-fixture.sql"
PRAGMA foreign_keys = ON;

DROP TRIGGER IF EXISTS people_touch;
DROP VIEW IF EXISTS people_directory;
DROP INDEX IF EXISTS idx_people_team;
DROP TABLE IF EXISTS people;
DROP TABLE IF EXISTS teams;

CREATE TABLE teams (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE people (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    team_id INTEGER REFERENCES teams(id) ON DELETE SET NULL,
    avatar BLOB,
    bio TEXT,
    score REAL DEFAULT 0,
    created_at TEXT
);

CREATE INDEX idx_people_team ON people(team_id);

CREATE VIEW people_directory AS
    SELECT p.id, p.name, t.name AS team
    FROM people p
    LEFT JOIN teams t ON t.id = p.team_id;

CREATE TRIGGER people_touch AFTER UPDATE ON people
BEGIN
    SELECT 1;
END;

INSERT INTO teams (name) VALUES ('Platform'), ('Data'), ('Design');

WITH RECURSIVE seq(value) AS (
    SELECT 1
    UNION ALL
    SELECT value + 1 FROM seq WHERE value < 60
)
INSERT INTO people (name, email, team_id, avatar, bio, score, created_at)
SELECT
    'Person ' || value,
    CASE WHEN value % 5 = 0 THEN NULL ELSE 'p' || value || '@example.com' END,
    CASE value % 4 WHEN 0 THEN NULL ELSE (value % 3) + 1 END,
    CASE value % 7 WHEN 0 THEN randomblob(12) ELSE NULL END,
    CASE
        WHEN value % 6 = 0 THEN NULL
        ELSE 'Row ' || value || ' - <b>unsafe</b> & more text ' || printf('%.*c', 200, 'x')
    END,
    value * 1.5,
    '2026-01-' || printf('%02d', (value % 28) + 1)
FROM seq;

-- Search escaping and Unicode/HTML reflection checks.
INSERT INTO people (name, email, team_id, avatar, bio, score)
VALUES ('100%_literal', 'zoe@example.com', 3, NULL, 'Zoë <script>alert(1)</script> is here', 42);

-- Empty-table state.
CREATE TABLE IF NOT EXISTS empty_table (id INTEGER PRIMARY KEY, note TEXT);
