#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$root/benchmarks"
mkdir -p "$out_dir"

OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}" \
OLLAMA_MODEL="${OLLAMA_MODEL:-}" \
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-embeddinggemma}" \
AI_BUDGET_TTFT_MS="${AI_BUDGET_TTFT_MS:-1500}" \
AI_BUDGET_TPS="${AI_BUDGET_TPS:-20}" \
AI_BUDGET_EMBED_8_MS="${AI_BUDGET_EMBED_8_MS:-500}" \
AI_BUDGET_MEMORY_SEARCH_MS="${AI_BUDGET_MEMORY_SEARCH_MS:-250}" \
MEMPALACE_QUERY="${MEMPALACE_QUERY:-vish local ai integration}" \
OUT_FILE="$out_dir/ai-$(date +%F).json" \
ruby <<'RUBY'
require "json"
require "net/http"
require "open3"
require "uri"

def now_ms
  Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
end

def ollama_base
  ENV.fetch("OLLAMA_BASE_URL").sub(%r{/api/?$}, "").sub(%r{/$}, "")
end

def http_json(method, url, payload = nil, read_timeout = 120)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = read_timeout
  request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(payload) if payload
  response = http.request(request)
  raise "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

def stream_chat(base, model)
  uri = URI("#{base}/api/chat")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = 180
  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate({
    model: model,
    stream: true,
    think: false,
    keep_alive: "5m",
    messages: [
      { role: "system", content: "Reply concisely." },
      { role: "user", content: "Say ready in one short sentence." }
    ],
    options: {
      temperature: 0,
      num_predict: 64
    }
  })

  started = now_ms
  first_token_ms = nil
  content_chars = 0
  final = {}
  buffer = +""

  http.request(request) do |response|
    raise "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    response.read_body do |chunk|
      buffer << chunk
      while (idx = buffer.index("\n"))
        line = buffer.slice!(0..idx).strip
        next if line.empty?
        item = JSON.parse(line)
        piece = item.dig("message", "content").to_s
        unless piece.empty?
          first_token_ms ||= now_ms - started
          content_chars += piece.length
        end
        final = item if item["done"]
      end
    end
  end

  unless buffer.strip.empty?
    item = JSON.parse(buffer)
    piece = item.dig("message", "content").to_s
    first_token_ms ||= now_ms - started unless piece.empty?
    content_chars += piece.length
    final = item if item["done"]
  end

  total_ms = now_ms - started
  eval_count = final.fetch("eval_count", 0).to_i
  eval_duration_ns = final.fetch("eval_duration", 0).to_i
  tokens_per_second = eval_duration_ns.positive? ? (eval_count / (eval_duration_ns / 1_000_000_000.0)) : 0.0

  {
    ok: true,
    first_token_ms: first_token_ms || total_ms,
    total_ms: total_ms,
    eval_count: eval_count,
    eval_duration_ns: eval_duration_ns,
    tokens_per_second: tokens_per_second.round(2),
    content_chars: content_chars,
    load_duration_ns: final.fetch("load_duration", 0)
  }
rescue StandardError => e
  { ok: false, error: e.message }
end

def embed(base, model)
  inputs = [
    "VISH opens apps quickly.",
    "Local AI must not block launcher search.",
    "Files are searched through Spotlight and a compact catalog.",
    "Snippets expand text from user-defined triggers.",
    "Clipboard history is opt-in.",
    "Universal Actions reveal files and copy paths.",
    "MemPalace stores local long-term AI memory.",
    "Ollama serves local models over HTTP."
  ]
  payload = {
    model: model,
    input: inputs,
    keep_alive: "5m"
  }
  started = now_ms
  response = http_json(:post, "#{base}/api/embed", payload)
  total_ms = now_ms - started
  embeddings = response.fetch("embeddings", [])
  {
    ok: true,
    model: response["model"] || model,
    total_ms: total_ms,
    count: embeddings.length,
    dimensions: embeddings.first&.length.to_i,
    reported_total_duration_ns: response["total_duration"]
  }
rescue StandardError => e
  { ok: false, model: model, error: e.message }
end

def command_exists?(name)
  system("command", "-v", name, out: File::NULL, err: File::NULL)
end

def mempalace_search
  return { ok: false, skipped: true, reason: "mempalace command not found" } unless command_exists?("mempalace")

  started = now_ms
  stdout, stderr, status = Open3.capture3("mempalace", "search", ENV.fetch("MEMPALACE_QUERY"), "--results", "5")
  total_ms = now_ms - started
  {
    ok: status.success?,
    total_ms: total_ms,
    stdout_bytes: stdout.bytesize,
    stderr: stderr.strip[0, 500],
    query: ENV.fetch("MEMPALACE_QUERY")
  }
rescue StandardError => e
  { ok: false, error: e.message }
end

def embedding_model_name?(name)
  name.downcase.match?(/embed|nomic|mxbai|minilm|bge|e5|qwen3-embedding/)
end

def chat_models(tags)
  Array(tags["models"]).map { |item| item["name"].to_s }.reject(&:empty?).reject { |name| embedding_model_name?(name) }
end

base = ollama_base
version = nil
tags = nil
model = ENV["OLLAMA_MODEL"].to_s.strip

begin
  version = http_json(:get, "#{base}/api/version", nil, 5)
  tags = http_json(:get, "#{base}/api/tags", nil, 10)
  if model.empty?
    model = chat_models(tags).first.to_s
  end
  raise "OLLAMA_MODEL must be a chat model, not an embedding model." if !model.empty? && embedding_model_name?(model)
  raise "Set OLLAMA_MODEL or install at least one chat Ollama model." if model.empty?
rescue StandardError => e
  data = {
    schema_version: 1,
    ok: false,
    error: e.message,
    ollama_base_url: base,
    note: "Start Ollama and install a model, then rerun. Example: OLLAMA_MODEL=qwen3 ./scripts/ai-benchmark.sh"
  }
  File.write(ENV.fetch("OUT_FILE"), JSON.pretty_generate(data))
  puts JSON.pretty_generate(data)
  exit 1
end

cold_chat = stream_chat(base, model)
warm_chat = cold_chat[:ok] ? stream_chat(base, model) : cold_chat
cold_embedding = embed(base, ENV.fetch("OLLAMA_EMBED_MODEL"))
warm_embedding = cold_embedding[:ok] ? embed(base, ENV.fetch("OLLAMA_EMBED_MODEL")) : cold_embedding
embedding = warm_embedding
memory = mempalace_search

ttft_budget = ENV.fetch("AI_BUDGET_TTFT_MS").to_f
tps_budget = ENV.fetch("AI_BUDGET_TPS").to_f
embed_budget = ENV.fetch("AI_BUDGET_EMBED_8_MS").to_f
memory_budget = ENV.fetch("AI_BUDGET_MEMORY_SEARCH_MS").to_f

data = {
  schema_version: 1,
  ok: warm_chat[:ok],
  ollama_base_url: base,
  ollama_version: version,
  selected_model: model,
  installed_models: Array(tags["models"]).map { |item| item["name"] }.compact,
  cold_chat: cold_chat,
  warm_chat: warm_chat,
  cold_embedding: cold_embedding,
  warm_embedding: warm_embedding,
  embedding: embedding,
  mempalace: memory,
  budgets: {
    first_token_ms: ttft_budget,
    tokens_per_second: tps_budget,
    embed_8_docs_ms: embed_budget,
    mempalace_search_ms: memory_budget
  },
  budget_status: {
    warm_first_token: warm_chat[:ok] && warm_chat[:first_token_ms].to_f <= ttft_budget,
    warm_tokens_per_second: warm_chat[:ok] && warm_chat[:tokens_per_second].to_f >= tps_budget,
    embed_8_docs: embedding[:ok] && embedding[:total_ms].to_f <= embed_budget,
    mempalace_search: memory[:skipped] || (memory[:ok] && memory[:total_ms].to_f <= memory_budget)
  },
  note: "AI benchmark only. Existing launcher budgets still require scripts/benchmark.sh and signpost traces."
}

File.write(ENV.fetch("OUT_FILE"), JSON.pretty_generate(data))
puts JSON.pretty_generate(data)
exit(warm_chat[:ok] ? 0 : 1)
RUBY
