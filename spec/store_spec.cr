require "./spec_helper"

describe Waypoints::Store do
  it "adds, lists, filters, and removes bookmarks in an isolated database" do
    SpecSupport.with_temp_db do |db_path|
      store = Waypoints::Store.new(db_path)
      begin
        older = Time.utc(2026, 7, 9, 10, 0, 0)
        newer = Time.utc(2026, 7, 10, 10, 0, 0)
        store.add("https://crystal-lang.org", "Crystal", ["Language", " docs "], "Reference", older)
        store.add("https://sqlite.org", "SQLite", ["database"], "Storage", newer)

        store.list.map(&.url).should eq([
          "https://sqlite.org",
          "https://crystal-lang.org",
        ])
        store.list("DOCS").map(&.url).should eq(["https://crystal-lang.org"])

        store.remove("https://sqlite.org")
        store.list.map(&.url).should eq(["https://crystal-lang.org"])
      ensure
        store.close
      end
    end
  end

  it "rejects duplicate URLs with a typed error" do
    SpecSupport.with_temp_db do |db_path|
      store = Waypoints::Store.new(db_path)
      begin
        store.add("https://example.com", "Example")
        expect_raises(Waypoints::BookmarkAlreadyExistsError, "bookmark already exists: https://example.com") do
          store.add("https://example.com", "Duplicate")
        end
      ensure
        store.close
      end
    end
  end

  it "reports a typed error when removing an absent URL" do
    SpecSupport.with_temp_db do |db_path|
      store = Waypoints::Store.new(db_path)
      begin
        expect_raises(Waypoints::BookmarkNotFoundError, "bookmark not found: https://missing.example") do
          store.remove("https://missing.example")
        end
      ensure
        store.close
      end
    end
  end
end
