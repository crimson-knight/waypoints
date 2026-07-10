require "./version"

module Waypoints
  # Dispatches waypoints commands and renders their results.
  class CLI
    # Runs the command-line arguments and returns a process exit status.
    def self.run(args : Array(String) = ARGV, output : IO = STDOUT, error : IO = STDERR) : Int32
      if args == ["version"]
        output.puts "waypoints #{VERSION}"
        return 0
      end

      error.puts "Usage: waypoints version"
      2
    end
  end
end
