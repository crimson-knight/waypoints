require "./store"
require "./version"

module Waypoints
  # Resolves the database location shared by the CLI and other callers.
  module DBPath
    DEFAULT_RELATIVE_PATH = File.join(".local", "share", "waypoints", "waypoints.db")

    # Resolves flag, environment, and home-directory paths in descending precedence.
    def self.resolve(flag_path : String? = nil, env_path : String? = ENV["WAYPOINTS_DB"]?,
                     home : String = Path.home.to_s) : String
      return flag_path unless flag_path.nil? || flag_path.empty?
      return env_path unless env_path.nil? || env_path.empty?

      File.join(home, DEFAULT_RELATIVE_PATH)
    end
  end

  # Raised when command-line arguments do not match a supported invocation.
  class UsageError < Error
  end

  # Dispatches waypoints commands and renders their results.
  class CLI
    USAGE = <<-TEXT
      Usage:
        waypoints [--db PATH] add <url> [--title T] [--tags a,b] [--notes N]
        waypoints [--db PATH] list [--tag t] [--json]
        waypoints [--db PATH] search <query> [--json]
        waypoints [--db PATH] describe <url>
        waypoints [--db PATH] rm <url>
        waypoints version
      TEXT

    # Runs the command-line arguments and returns a process exit status.
    def self.run(args : Array(String) = ARGV, output : IO = STDOUT, error : IO = STDERR,
                 env : Hash(String, String) = ENV.to_h, home : String = Path.home.to_s) : Int32
      flag_path, command_args = extract_db_path(args)
      command = command_args.shift?

      case command
      when "add"
        run_add(command_args, DBPath.resolve(flag_path, env["WAYPOINTS_DB"]?, home), output)
      when "list"
        run_list(command_args, DBPath.resolve(flag_path, env["WAYPOINTS_DB"]?, home), output)
      when "search"
        run_search(command_args, DBPath.resolve(flag_path, env["WAYPOINTS_DB"]?, home), output)
      when "rm"
        run_rm(command_args, DBPath.resolve(flag_path, env["WAYPOINTS_DB"]?, home), output)
      when "version"
        raise UsageError.new("version does not accept arguments") unless command_args.empty?

        output.puts "waypoints #{VERSION}"
        0
      else
        raise UsageError.new(command ? "unknown command: #{command}" : "a command is required")
      end
    rescue ex : UsageError
      error.puts "Error: #{ex.message}"
      error.puts USAGE
      2
    rescue ex : Error
      error.puts "Error: #{ex.message}"
      1
    end

    # Parses and executes the add command.
    private def self.run_add(args : Array(String), db_path : String, output : IO) : Int32
      url : String? = nil
      title : String? = nil
      tags = [] of String
      notes = ""
      index = 0

      while index < args.size
        argument = args[index]
        case argument
        when "--title"
          title = required_option_value(args, index, "--title")
          index += 2
        when "--tags"
          tags = required_option_value(args, index, "--tags").split(',')
          index += 2
        when "--notes"
          notes = required_option_value(args, index, "--notes")
          index += 2
        else
          if argument.starts_with?("--title=")
            title = argument.lchop("--title=")
          elsif argument.starts_with?("--tags=")
            tags = argument.lchop("--tags=").split(',')
          elsif argument.starts_with?("--notes=")
            notes = argument.lchop("--notes=")
          elsif argument.starts_with?("-")
            raise UsageError.new("unknown add option: #{argument}")
          elsif url
            raise UsageError.new("add accepts exactly one URL")
          else
            url = argument
          end
          index += 1
        end
      end

      raise UsageError.new("add requires a URL") unless url

      store = Store.new(db_path)
      begin
        bookmark = store.add(url, title || url, tags, notes)
        output.puts "Added #{bookmark.url}"
      ensure
        store.close
      end
      0
    end

    # Parses and executes the list command.
    private def self.run_list(args : Array(String), db_path : String, output : IO) : Int32
      tag : String? = nil
      json = false
      index = 0

      while index < args.size
        argument = args[index]
        case argument
        when "--tag"
          tag = required_option_value(args, index, "--tag")
          index += 2
        when "--json"
          json = true
          index += 1
        else
          if argument.starts_with?("--tag=")
            tag = argument.lchop("--tag=")
            index += 1
          else
            raise UsageError.new("unknown list argument: #{argument}")
          end
        end
      end

      store = Store.new(db_path)
      begin
        render_bookmarks(store.list(tag), json, output)
      ensure
        store.close
      end
      0
    end

    # Parses and executes the search command over the FTS5 index.
    private def self.run_search(args : Array(String), db_path : String, output : IO) : Int32
      query_parts = [] of String
      json = false
      index = 0

      while index < args.size
        argument = args[index]
        case argument
        when "--json"
          json = true
        when "--"
          # Everything after a bare -- is a literal query term.
          index += 1
          while index < args.size
            query_parts << args[index]
            index += 1
          end
          break
        else
          raise UsageError.new("unknown search option: #{argument}") if argument.starts_with?("-")

          query_parts << argument
        end
        index += 1
      end

      query = query_parts.join(" ")
      raise UsageError.new("search requires a query") if query.strip.empty?

      store = Store.new(db_path)
      begin
        render_bookmarks(store.search(query), json, output)
      ensure
        store.close
      end
      0
    end

    # Parses and executes the rm command.
    private def self.run_rm(args : Array(String), db_path : String, output : IO) : Int32
      url : String? = nil

      args.each do |argument|
        raise UsageError.new("unknown rm option: #{argument}") if argument.starts_with?("-")
        raise UsageError.new("rm accepts exactly one URL") if url

        url = argument
      end

      raise UsageError.new("rm requires a URL") unless url

      store = Store.new(db_path)
      begin
        store.remove(url)
        output.puts "Removed #{url}"
      ensure
        store.close
      end
      0
    end

    # Removes the global database option while retaining command argument order.
    private def self.extract_db_path(args : Array(String)) : {String?, Array(String)}
      db_path : String? = nil
      remaining = [] of String
      index = 0

      while index < args.size
        argument = args[index]
        if argument == "--db"
          db_path = required_option_value(args, index, "--db")
          index += 2
        elsif argument.starts_with?("--db=")
          db_path = argument.lchop("--db=")
          raise UsageError.new("--db requires a path") if db_path.empty?
          index += 1
        else
          remaining << argument
          index += 1
        end
      end

      {db_path, remaining}
    end

    # Reads the value following an option or raises a typed usage error.
    private def self.required_option_value(args : Array(String), index : Int32, option : String) : String
      value = args[index + 1]?
      raise UsageError.new("#{option} requires a value") unless value

      value
    end

    # Emits either a stable JSON array or a compact human-readable listing.
    private def self.render_bookmarks(bookmarks : Array(Bookmark), json : Bool, output : IO) : Nil
      if json
        bookmarks.to_json(output)
        output.puts
      elsif bookmarks.empty?
        output.puts "No bookmarks."
      else
        bookmarks.each do |bookmark|
          output.puts bookmark.title
          output.puts "  URL: #{bookmark.url}"
          output.puts "  Tags: #{bookmark.tags.join(", ")}"
          output.puts "  Notes: #{bookmark.notes}" unless bookmark.notes.empty?
          output.puts "  Created: #{bookmark.created_at}"
        end
      end
    end
  end
end
