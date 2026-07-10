require "db"
require "json"
require "sqlite3"

module Waypoints
  # Base class for failures with a user-actionable waypoints meaning.
  class Error < Exception
  end

  # Raised when a bookmark URL is already present in the store.
  class BookmarkAlreadyExistsError < Error
    # Builds an error naming the duplicate URL.
    def initialize(url : String)
      super("bookmark already exists: #{url}")
    end
  end

  # Raised when a requested bookmark URL is absent from the store.
  class BookmarkNotFoundError < Error
    # Builds an error naming the missing URL.
    def initialize(url : String)
      super("bookmark not found: #{url}")
    end
  end

  # A bookmark row with its comma-joined tags decoded for callers.
  struct Bookmark
    include JSON::Serializable

    getter url : String
    getter title : String
    getter tags : Array(String)
    getter notes : String
    getter created_at : String

    # Builds a bookmark from values returned by the store.
    def initialize(@url : String, @title : String, @tags : Array(String), @notes : String, @created_at : String)
    end
  end

  # Owns the SQLite bookmark database and keeps its external-content FTS5 table synchronized.
  class Store
    @db : DB::Database

    # Opens the database at *db_path*, creating its parent directory and schema when needed.
    def initialize(@db_path : String)
      directory = File.dirname(@db_path)
      Dir.mkdir_p(directory) unless directory.empty? || Dir.exists?(directory)
      @db = DB.open("sqlite3://#{@db_path}")
      create_schema
    end

    # Closes the underlying database connection.
    def close : Nil
      @db.close
    end

    # Adds a bookmark, normalizing tags for exact filtering and FTS search.
    def add(url : String, title : String, tags : Array(String) = [] of String, notes : String = "",
            created_at : Time = Time.utc) : Bookmark
      normalized_tags = normalize_tags(tags)
      timestamp = created_at.to_rfc3339
      result = @db.exec(
        "INSERT OR IGNORE INTO bookmarks (url, title, tags, notes, created_at) VALUES (?, ?, ?, ?, ?)",
        url, title, normalized_tags.join(","), notes, timestamp
      )
      raise BookmarkAlreadyExistsError.new(url) if result.rows_affected == 0

      Bookmark.new(url, title, normalized_tags, notes, timestamp)
    end

    # Lists bookmarks newest first, optionally retaining only exact normalized tag matches.
    def list(tag : String? = nil) : Array(Bookmark)
      bookmarks = [] of Bookmark
      @db.query_each(
        "SELECT url, title, tags, notes, created_at FROM bookmarks ORDER BY created_at DESC, url ASC"
      ) do |rs|
        bookmarks << bookmark_from(rs)
      end

      return bookmarks unless tag

      normalized_tag = tag.strip.downcase
      bookmarks.select { |bookmark| bookmark.tags.includes?(normalized_tag) }
    end

    # Ranks bookmarks by FTS5 bm25 over title, tags, and notes (lower score first).
    #
    # Tokens are sanitized to bare `[a-z0-9_]` words before being ANDed into the
    # MATCH expression, so raw query punctuation can never form FTS5 operators.
    # A query with no usable tokens returns an empty result rather than raising.
    def search(query : String, limit : Int32 = 50) : Array(Bookmark)
      tokens = sanitize_tokens(query)
      return [] of Bookmark if tokens.empty?

      match = tokens.join(" ")
      bookmarks = [] of Bookmark
      @db.query_each(
        "SELECT b.url, b.title, b.tags, b.notes, b.created_at " \
        "FROM bookmarks_fts JOIN bookmarks b ON b.id = bookmarks_fts.rowid " \
        "WHERE bookmarks_fts MATCH ? ORDER BY bm25(bookmarks_fts) ASC LIMIT ?",
        match, limit
      ) do |rs|
        bookmarks << bookmark_from(rs)
      end
      bookmarks
    end

    # Removes the bookmark for *url*, raising BookmarkNotFoundError when it does not exist.
    def remove(url : String) : Nil
      result = @db.exec("DELETE FROM bookmarks WHERE url = ?", url)
      raise BookmarkNotFoundError.new(url) if result.rows_affected == 0
    end

    # Converts one result row into the public bookmark representation.
    private def bookmark_from(rs : DB::ResultSet) : Bookmark
      url = rs.read(String)
      title = rs.read(String)
      tags = split_tags(rs.read(String))
      notes = rs.read(String)
      created_at = rs.read(String)
      Bookmark.new(url, title, tags, notes, created_at)
    end

    # Produces stable, case-insensitive tag values without blank entries.
    private def normalize_tags(tags : Array(String)) : Array(String)
      tags.map(&.strip.downcase).reject(&.empty?).uniq
    end

    # Decodes a normalized comma-joined tags column.
    private def split_tags(tags : String) : Array(String)
      tags.empty? ? [] of String : tags.split(',')
    end

    # Reduces a free-text query to bare lowercase word tokens safe for FTS5 MATCH.
    private def sanitize_tokens(query : String) : Array(String)
      query.downcase.scan(/[a-z0-9_]+/).map(&.[0])
    end

    # Creates the base table, external-content FTS5 table, and synchronization triggers.
    private def create_schema : Nil
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS bookmarks (
          id INTEGER PRIMARY KEY,
          url TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          tags TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
        SQL

      @db.exec <<-SQL
        CREATE VIRTUAL TABLE IF NOT EXISTS bookmarks_fts USING fts5(
          title, tags, notes, content='bookmarks', content_rowid='id'
        )
        SQL

      @db.exec <<-SQL
        CREATE TRIGGER IF NOT EXISTS bookmarks_ai AFTER INSERT ON bookmarks BEGIN
          INSERT INTO bookmarks_fts(rowid, title, tags, notes) VALUES (new.id, new.title, new.tags, new.notes);
        END;
        SQL

      @db.exec <<-SQL
        CREATE TRIGGER IF NOT EXISTS bookmarks_ad AFTER DELETE ON bookmarks BEGIN
          INSERT INTO bookmarks_fts(bookmarks_fts, rowid, title, tags, notes) VALUES ('delete', old.id, old.title, old.tags, old.notes);
        END;
        SQL

      @db.exec <<-SQL
        CREATE TRIGGER IF NOT EXISTS bookmarks_au AFTER UPDATE ON bookmarks BEGIN
          INSERT INTO bookmarks_fts(bookmarks_fts, rowid, title, tags, notes) VALUES ('delete', old.id, old.title, old.tags, old.notes);
          INSERT INTO bookmarks_fts(rowid, title, tags, notes) VALUES (new.id, new.title, new.tags, new.notes);
        END;
        SQL

      migrate_add_notes_embedding
    end

    # Adds the nullable notes_embedding BLOB column when an older database
    # predates it. Idempotent: existing databases are upgraded in place, new
    # ones already have the column from a prior run of this migration.
    private def migrate_add_notes_embedding : Nil
      return if column_exists?("bookmarks", "notes_embedding")

      @db.exec "ALTER TABLE bookmarks ADD COLUMN notes_embedding BLOB"
    end

    # True when *table* already has a column named *column*.
    private def column_exists?(table : String, column : String) : Bool
      count = @db.scalar(
        "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?", table, column
      ).as(Int64)
      count > 0
    end
  end
end
