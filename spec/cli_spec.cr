require "./spec_helper"
require "../src/waypoints/cli"

private def run_cli(args : Array(String), env = {} of String => String) : NamedTuple(status: Int32, output: String, error: String)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Waypoints::CLI.run(args, output, error, env, "/unused-home")
  {status: status, output: output.to_s, error: error.to_s}
end

describe Waypoints::CLI do
  it "adds bookmarks with URL title defaults and lists an exact tag" do
    SpecSupport.with_temp_db do |db_path|
      first = run_cli(["--db", db_path, "add", "https://crystal-lang.org", "--tags", "language,docs"])
      second = run_cli(["add", "https://sqlite.org", "--db", db_path, "--title", "SQLite", "--tags", "database"])
      listing = run_cli(["--db", db_path, "list", "--tag", "docs"])

      first.should eq({status: 0, output: "Added https://crystal-lang.org\n", error: ""})
      second[:status].should eq(0)
      listing[:status].should eq(0)
      listing[:output].should contain("https://crystal-lang.org\n")
      listing[:output].should_not contain("https://sqlite.org")
    end
  end

  it "searches the full-text index and joins multi-word queries" do
    SpecSupport.with_temp_db do |db_path|
      run_cli(["--db", db_path, "add", "https://crystal-lang.org", "--title", "Crystal", "--notes", "compiled language"])
      run_cli(["--db", db_path, "add", "https://sqlite.org", "--title", "SQLite", "--notes", "embedded database"])

      hit = run_cli(["--db", db_path, "search", "embedded", "database"])
      hit[:status].should eq(0)
      hit[:output].should contain("https://sqlite.org")
      hit[:output].should_not contain("https://crystal-lang.org")

      empty = run_cli(["--db", db_path, "search", "nonexistentterm"])
      empty[:status].should eq(0)
      empty[:output].should eq("No bookmarks.\n")
    end
  end

  it "removes a bookmark and reports a typed error for an unknown URL" do
    SpecSupport.with_temp_db do |db_path|
      run_cli(["--db", db_path, "add", "https://example.com", "--title", "Example"])

      removed = run_cli(["--db", db_path, "rm", "https://example.com"])
      removed.should eq({status: 0, output: "Removed https://example.com\n", error: ""})

      listing = run_cli(["--db", db_path, "list"])
      listing[:output].should eq("No bookmarks.\n")

      missing = run_cli(["--db", db_path, "rm", "https://example.com"])
      missing[:status].should eq(1)
      missing[:error].should contain("bookmark not found: https://example.com")
    end
  end

  it "reports a usage error and exit code 2 for an unknown command" do
    result = run_cli(["frobnicate"])
    result[:status].should eq(2)
    result[:error].should contain("unknown command: frobnicate")
  end

  it "emits list JSON as an array of bookmark objects" do
    SpecSupport.with_temp_db do |db_path|
      run_cli(["--db", db_path, "add", "https://example.com", "--title", "Example", "--tags", "reference,web", "--notes", "Read later"])
      result = run_cli(["--db", db_path, "list", "--json"])

      result[:status].should eq(0)
      result[:error].should be_empty
      json = JSON.parse(result[:output]).as_a
      json.size.should eq(1)
      json.first.as_h.keys.sort.should eq(["created_at", "notes", "tags", "title", "url"])
      json.first["url"].as_s.should eq("https://example.com")
      json.first["tags"].as_a.map(&.as_s).should eq(["reference", "web"])
    end
  end
end
