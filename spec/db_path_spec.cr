require "./spec_helper"
require "../src/waypoints/cli"

describe Waypoints::DBPath do
  it "gives the flag precedence over the environment and default" do
    Waypoints::DBPath.resolve("/flag/waypoints.db", "/env/waypoints.db", "/home/test").should eq("/flag/waypoints.db")
  end

  it "uses the environment when no flag is present" do
    Waypoints::DBPath.resolve(nil, "/env/waypoints.db", "/home/test").should eq("/env/waypoints.db")
  end

  it "uses the XDG-style path beneath home by default" do
    Waypoints::DBPath.resolve(nil, nil, "/home/test").should eq("/home/test/.local/share/waypoints/waypoints.db")
  end
end
