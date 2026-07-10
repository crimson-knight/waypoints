require "./spec_helper"
require "../src/waypoints/cli"

# A fetcher that returns canned page content without any network access.
private class FakeFetcher < Waypoints::PageFetcher
  def initialize(@page : Waypoints::PageContent)
  end

  def fetch(url : String) : Waypoints::PageContent
    @page
  end
end

# A model seam whose `real?` and structured output are fixed by the spec.
private class FakeModel < Waypoints::DescriptionModel
  def initialize(@real : Bool, @description : Waypoints::BookmarkDescription? = nil)
  end

  def real? : Bool
    @real
  end

  def describe(page : Waypoints::PageContent) : Waypoints::BookmarkDescription
    @description || raise "FakeModel#describe called without a canned description"
  end
end

private def run_describe(args, fetcher, model) : NamedTuple(status: Int32, output: String, error: String)
  output = IO::Memory.new
  error = IO::Memory.new
  # Wire the describer's diagnostic stream to the same captured error IO the CLI
  # uses, mirroring how the production path builds the describer with `error`.
  describer = Waypoints::Describer.new(fetcher, model, error)
  status = Waypoints::CLI.run(args, output, error, {} of String => String, "/unused-home", describer)
  {status: status, output: output.to_s, error: error.to_s}
end

describe "waypoints describe" do
  it "saves the model's structured description when the bridge is real" do
    SpecSupport.with_temp_db do |db_path|
      page = Waypoints::PageContent.new("https://crystal-lang.org", "Crystal Programming Language", "A language for humans and computers.")
      model = FakeModel.new(true, Waypoints::BookmarkDescription.new(
        title: "The Crystal Programming Language",
        tags: ["crystal", "language"],
        summary: "A statically typed, compiled language with Ruby-like syntax."
      ))

      result = run_describe(["--db", db_path, "describe", "https://crystal-lang.org"], FakeFetcher.new(page), model)

      result[:status].should eq(0)
      result[:output].should contain("Added https://crystal-lang.org")
      result[:output].should contain("The Crystal Programming Language")
      result[:output].should contain("crystal, language")

      store = Waypoints::Store.new(db_path)
      begin
        saved = store.list.first
        saved.title.should eq("The Crystal Programming Language")
        saved.tags.should eq(["crystal", "language"])
        saved.notes.should eq("A statically typed, compiled language with Ruby-like syntax.")
      ensure
        store.close
      end
    end
  end

  it "falls back to a heuristic and announces the mock bridge when not real" do
    SpecSupport.with_temp_db do |db_path|
      page = Waypoints::PageContent.new("https://sqlite.org/fts5.html", "SQLite FTS5 Extension", "Full-text search for SQLite.")

      result = run_describe(["--db", db_path, "describe", "https://sqlite.org/fts5.html"], FakeFetcher.new(page), FakeModel.new(false))

      result[:status].should eq(0)
      result[:error].should contain("(llamero mock bridge — heuristic description used)")
      result[:output].should contain("SQLite FTS5 Extension")

      store = Waypoints::Store.new(db_path)
      begin
        saved = store.list.first
        saved.title.should eq("SQLite FTS5 Extension")
        saved.tags.should eq(["sqlite"]) # host-derived heuristic tag
        saved.notes.should eq("SQLite FTS5 Extension")
      ensure
        store.close
      end
    end
  end

  it "surfaces a model error as a clean exit code 1" do
    SpecSupport.with_temp_db do |db_path|
      page = Waypoints::PageContent.new("https://example.com", "Example", "text")

      # A model that reports real but always fails to describe is surfaced as exit 1.
      result = run_describe(["--db", db_path, "describe", "https://example.com"], FakeFetcher.new(page), RaisingModel.new)

      result[:status].should eq(1)
      result[:error].should contain("model offline")
    end
  end
end

# A model that reports real but always fails to describe, like a missing model.
private class RaisingModel < Waypoints::DescriptionModel
  def real? : Bool
    true
  end

  def describe(page : Waypoints::PageContent) : Waypoints::BookmarkDescription
    raise Waypoints::DescribeError.new("model offline")
  end
end
