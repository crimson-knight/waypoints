# Dogfood proof: teach a small local model how to use waypoints itself, then
# package that knowledge as a distributable "training filter".
#
#   crystal build --no-codegen examples/train_waypoints_adapter.cr   # type check (CI-safe)
#   crystal run examples/train_waypoints_adapter.cr                   # actually train
#   crystal run examples/train_waypoints_adapter.cr -- mlx-community/Qwen3-0.6B-4bit
#
# This file is written to COMPILE anywhere (it is part of the demo's proof that
# the docs->training-material pipeline is real), but RUNNING it requires Apple
# Silicon with the built llamero MLX bridge plus the model weights. Without the
# bridge it aborts early with a clear message rather than pretending to train.
#
# Use a DENSE base model. Gemma-4 e-series (e2b/e4b, MatFormer-style elastic)
# models train to low loss but the adapter has no effect at inference (a known
# upstream limitation), so a dense model like Qwen3-0.6B-4bit is the default.
#
# The pattern: waypoints ships its docs both as agent skills AND as a golden
# Q&A dataset, so even a tiny on-device model can be turned into a waypoints
# expert with no in-context teaching.
require "llamero"

MODEL = ARGV[0]? || "mlx-community/Qwen3-0.6B-4bit"
PAIRS = Path[__DIR__].parent.join("training_data", "waypoints_api_qa.jsonl")

# Probe questions paired with an exact waypoints fact the base model cannot
# guess from the question text alone.
PROBES = [
  {"What ranking does waypoints search use?", "bm25"},
  {"What environment variable overrides the waypoints database path?", "WAYPOINTS_DB"},
  {"What does waypoints print when the llamero bridge is a mock?", "heuristic"},
]

bridge = Llamero::Native::MLXBridge.try_load
unless bridge
  abort "MLX bridge dylib not found. Build it with: cd lib/llamero/native/llamero-mlx && ./build.sh"
end

runtime = Llamero::Native::MLXRuntime.new(model_id: MODEL, bridge: bridge)
session = runtime.start_session
puts "loading #{MODEL}..."
session.load_model
puts "loaded."

ask = ->(question : String) do
  response = session.chat([Llamero::Message.user(question)], max_tokens: 200)
  response.content.gsub(/<think>.*?<\/think>/m, "").strip
end

score = ->(label : String) do
  hits = 0
  PROBES.each do |question, expected|
    answer = ask.call(question)
    hit = answer.downcase.includes?(expected.downcase)
    hits += 1 if hit
    puts "  [#{hit ? "PASS" : "miss"}] #{question}"
    puts "         -> #{answer[0, 160].gsub('\n', ' ')}"
  end
  puts "[#{label}] #{hits}/#{PROBES.size} probes answered with the exact fact"
  hits
end

puts "\n--- before training ---"
before_hits = score.call("base model")

dataset = Llamero::Native::TrainingDataset.from_pairs_jsonl(
  PAIRS,
  system_prompt: "You are an expert on waypoints, the Crystal bookmarks CLI. Answer with exact waypoints commands, flags, and API names.",
  format: Llamero::Native::TrainingDataset.template_for(MODEL)
)
puts "\ndataset: #{dataset.size} prompt/completion pairs from #{PAIRS}"

config = Llamero::Native::AdapterTrainingConfig.new
config.iterations = 200
config.batch_size = 2
config.learning_rate = 1e-4
config.steps_per_report = 25

puts "training 'waypoints' adapter (#{config.iterations} iterations)..."
descriptor = session.train_adapter("waypoints", dataset, config) do |progress|
  puts "  iter #{progress.iteration}/#{progress.total_iterations}: loss=#{progress.loss.round(3)}"
end
summary = session.last_training.not_nil!
puts "trained -> #{descriptor.path} (final loss=#{summary.final_loss.round(3)})"

session.activate_adapters(
  Llamero::Native::AdapterStack.additive([Llamero::Native::AdapterSlot.new("waypoints")])
)
puts "\n--- with waypoints adapter ---"
with_hits = score.call("adapter active")
session.deactivate_adapters

# Package the trained adapter as a portable, verifiable training filter so any
# consumer with the same base model can activate waypoints expertise offline.
dest = Path[__DIR__].parent.join("dist", "waypoints.filter")
filter = Llamero::Native::TrainingFilter.pack(
  adapter_dir: descriptor.path,
  dest: dest,
  name: "waypoints",
  version: "0.1.0",
  base_model: MODEL,
  lora: Llamero::Native::TrainingFilter::LoRASpec.new(
    rank: config.rank, scale: config.scale, num_layers: config.num_layers
  ),
  provenance: Llamero::Native::TrainingFilter::Provenance.new(
    methods: ["sft"], generator: "waypoints/examples/train_waypoints_adapter.cr"
  ),
  library: "waypoints",
  library_version: "0.1.0",
  metrics: {"probe_hits" => with_hits.to_f}
)
runtime.close

puts "\npacked #{filter.id} -> #{dest} (checksum #{filter.manifest.weights_checksum})"
puts "probe hits: before=#{before_hits} with_adapter=#{with_hits}"
if with_hits > before_hits
  puts "\nWAYPOINTS ADAPTER TRAINED AND PACKAGED"
else
  abort "\nadapter did not improve probe accuracy — inspect the dataset or base model"
end
