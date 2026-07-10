require "spec"
require "file_utils"
require "random/secure"
require "../src/waypoints/store"

module SpecSupport
  # Yields a unique database path and removes its temporary directory afterward.
  def self.with_temp_db(& : String ->) : Nil
    directory = File.join(Dir.tempdir, "waypoints-spec-#{Random::Secure.hex(8)}")
    Dir.mkdir_p(directory)
    begin
      yield File.join(directory, "waypoints.db")
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
