#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <trace.trace|export.xml> [xpath]" >&2
  echo "default xpath targets signpost/points-of-interest tables from xctrace export" >&2
  exit 2
fi

input="$1"
xpath="${2:-//table[contains(translate(@schema,'SIGNPOSTPOINTS','signpostpoints'),'signpost') or contains(translate(@schema,'SIGNPOSTPOINTS','signpostpoints'),'points')]}"
tmp=""

cleanup() {
  [[ -n "$tmp" && -f "$tmp" ]] && rm -f "$tmp"
}
trap cleanup EXIT

if [[ "$input" == *.trace || -d "$input" ]]; then
  tmp="$(mktemp)"
  if ! xcrun xctrace export --quiet --input "$input" --xpath "$xpath" --output "$tmp" 2>/dev/null; then
    echo "No signpost table matched. Inspect available tables with:" >&2
    echo "  xcrun xctrace export --input '$input' --toc | rg -i 'signpost|point|log'" >&2
    exit 1
  fi
  input="$tmp"
fi

ruby -rrexml/document -e '
targets = %w[HotkeyToFrame KeystrokeToRender Search SpotlightQuery]
samples = Hash.new { |hash, key| hash[key] = [] }
doc = REXML::Document.new(File.read(ARGV.fetch(0)))

def walk(element, out)
  out << element.text.to_s
  element.attributes.each_attribute { |attr| out << attr.value.to_s }
  element.each_element { |child| walk(child, out) }
end

def duration_ms(row)
  values = []
  walk(row, values)
  named = values.each_cons(2).find { |name, _| name.to_s.downcase.include?("duration") }
  candidates = []
  candidates << named[1] if named
  candidates.concat(values)

  candidates.each do |value|
    text = value.to_s.strip
    next if text.empty?
    return $1.to_f if text =~ /\A([0-9]+(?:\.[0-9]+)?)\s*ms\z/i
    return $1.to_f / 1_000.0 if text =~ /\A([0-9]+(?:\.[0-9]+)?)\s*(?:us|µs)\z/i
    return $1.to_f * 1_000.0 if text =~ /\A([0-9]+(?:\.[0-9]+)?)\s*s\z/i
  end
  nil
end

doc.elements.each("//row") do |row|
  values = []
  walk(row, values)
  text = values.join(" ")
  target = targets.find { |name| text.include?(name) }
  next unless target
  ms = duration_ms(row)
  samples[target] << ms if ms && ms.finite? && ms >= 0
end

def percentile(values, p)
  sorted = values.sort
  return nil if sorted.empty?
  sorted[((sorted.length - 1) * p).ceil]
end

puts "metric,count,p50_ms,p95_ms"
targets.each do |target|
  values = samples[target]
  next if values.empty?
  puts [target, values.length, format("%.3f", percentile(values, 0.50)), format("%.3f", percentile(values, 0.95))].join(",")
end

if samples.values.all?(&:empty?)
  warn "No vish signpost rows found in #{ARGV.fetch(0)}"
  exit 1
end
' "$input"
