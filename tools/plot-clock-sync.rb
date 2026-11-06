#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"

abort "usage: #{$PROGRAM_NAME} INPUT.jsonl OUTPUT.svg" unless ARGV.length == 2

input_path, output_path = ARGV
samples = File.foreach(input_path).each_with_object([]) do |line, result|
  begin
    record = JSON.parse(line)
    next unless record["event"] == "clock_sync"

    result << {
      time_ns: record.fetch("host_monotonic_ns").to_f,
      offset_ms: record.fetch("offset_ms").to_f,
      rtt_ms: record.fetch("rtt_ms").to_f,
      drift_ppm: record.fetch("drift_ppm").to_f
    }
  rescue JSON::ParserError, KeyError
    next
  end
end
abort "no clock_sync records in #{input_path}" if samples.empty?

start_ns = samples.first.fetch(:time_ns)
start_offset_ms = samples.first.fetch(:offset_ms)
samples.each do |sample|
  sample[:minutes] = (sample.fetch(:time_ns) - start_ns) / 60_000_000_000.0
  sample[:offset_delta_ms] = sample.fetch(:offset_ms) - start_offset_ms
end

def median(values)
  sorted = values.sort
  middle = sorted.length / 2
  sorted.length.odd? ? sorted.fetch(middle) : (sorted.fetch(middle - 1) + sorted.fetch(middle)) / 2.0
end

def tick_values(minimum, maximum, count = 4)
  return [minimum] if minimum == maximum

  Array.new(count) { |index| minimum + ((maximum - minimum) * index / (count - 1).to_f) }
end

def padded_extent(values, minimum_padding)
  minimum, maximum = values.minmax
  padding = [(maximum - minimum) * 0.12, minimum_padding].max
  [minimum - padding, maximum + padding]
end

width = 960
height = 740
left = 92
right = 40
plot_width = width - left - right
panel_height = 146
panel_tops = [92, 302, 512]
duration_minutes = samples.last.fetch(:minutes)

panels = [
  {
    key: :offset_delta_ms,
    label: "Offset change from first estimate (ms)",
    extent: padded_extent(samples.map { |sample| sample.fetch(:offset_delta_ms) }, 0.05),
    color: "#0868ac",
    format: "%.2f"
  },
  {
    key: :rtt_ms,
    label: "Clock exchange round-trip time (ms)",
    extent: padded_extent(samples.map { |sample| sample.fetch(:rtt_ms) }, 0.05),
    color: "#238b45",
    format: "%.2f"
  },
  {
    key: :drift_ppm,
    label: "Estimated clock drift (ppm; display clipped to ±100)",
    extent: [-100.0, 100.0],
    color: "#6a51a3",
    format: "%.0f"
  }
]

x_at = lambda do |minutes|
  left + (duration_minutes.zero? ? 0.0 : minutes / duration_minutes * plot_width)
end

svg = []
svg << %(<?xml version="1.0" encoding="UTF-8"?>)
svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" role="img">)
svg << %(<title>Physical iPhone clock synchronization stability</title>)
svg << %(<desc>Three time-series plots over #{format('%.1f', duration_minutes)} minutes show controller clock offset change, clock exchange round-trip time, and estimated drift. Extreme startup drift values are clipped and annotated.</desc>)
svg << %(<rect width="#{width}" height="#{height}" fill="#ffffff"/>)
svg << %(<text x="#{left}" y="30" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="20" font-weight="600" fill="#111827">Physical iPhone clock stability</text>)
svg << %(<text x="#{left}" y="52" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="12" fill="#4b5563">#{samples.length} synchronization observations · #{format('%.1f', duration_minutes)} minutes · monotonic four-timestamp exchange</text>)

panels.each_with_index do |panel, panel_index|
  top = panel_tops.fetch(panel_index)
  bottom = top + panel_height
  y_min, y_max = panel.fetch(:extent)
  y_at = lambda do |value|
    clamped = [[value, y_min].max, y_max].min
    bottom - ((clamped - y_min) / (y_max - y_min) * panel_height)
  end

  svg << %(<text x="#{left}" y="#{top - 14}" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="13" font-weight="600" fill="#111827">#{CGI.escapeHTML(panel.fetch(:label))}</text>)
  svg << %(<rect x="#{left}" y="#{top}" width="#{plot_width}" height="#{panel_height}" fill="#ffffff" stroke="#9ca3af" stroke-width="1"/>)

  tick_values(y_min, y_max).each do |tick|
    y = y_at.call(tick)
    svg << %(<line x1="#{left}" y1="#{format('%.2f', y)}" x2="#{left + plot_width}" y2="#{format('%.2f', y)}" stroke="#e5e7eb" stroke-width="1"/>)
    svg << %(<text x="#{left - 9}" y="#{format('%.2f', y + 4)}" text-anchor="end" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="11" fill="#4b5563">#{format(panel.fetch(:format), tick)}</text>)
  end

  tick_values(0.0, duration_minutes, 6).each do |tick|
    x = x_at.call(tick)
    svg << %(<line x1="#{format('%.2f', x)}" y1="#{top}" x2="#{format('%.2f', x)}" y2="#{bottom}" stroke="#f3f4f6" stroke-width="1"/>)
    if panel_index == panels.length - 1
      svg << %(<text x="#{format('%.2f', x)}" y="#{bottom + 18}" text-anchor="middle" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="11" fill="#4b5563">#{format('%.1f', tick)}</text>)
    end
  end

  points = samples.map do |sample|
    [x_at.call(sample.fetch(:minutes)), y_at.call(sample.fetch(panel.fetch(:key)))]
  end
  points_attribute = points.map { |x, y| "#{format('%.2f', x)},#{format('%.2f', y)}" }.join(" ")
  svg << %(<polyline points="#{points_attribute}" fill="none" stroke="#{panel.fetch(:color)}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>)

  next unless panel.fetch(:key) == :drift_ppm

  samples.select { |sample| sample.fetch(:drift_ppm).abs > 100.0 }.each do |sample|
    svg << %(<circle cx="#{format('%.2f', x_at.call(sample.fetch(:minutes)))}" cy="#{format('%.2f', y_at.call(sample.fetch(:drift_ppm)))}" r="3.5" fill="#b91c1c"/>)
  end
end

drifts = samples.map { |sample| sample.fetch(:drift_ppm) }
offsets = samples.map { |sample| sample.fetch(:offset_delta_ms) }
rtts = samples.map { |sample| sample.fetch(:rtt_ms) }
clipped_count = drifts.count { |value| value.abs > 100.0 }
svg << %(<text x="#{left + plot_width / 2}" y="#{height - 29}" text-anchor="middle" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="12" fill="#111827">Elapsed time (minutes)</text>)
svg << %(<text x="#{left}" y="#{height - 8}" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="11" fill="#4b5563">Median RTT #{format('%.3f', median(rtts))} ms · offset range #{format('%.3f', offsets.min)} to #{format('%.3f', offsets.max)} ms · #{clipped_count} pre-fix startup drift observations clipped (raw minimum #{format('%.0f', drifts.min)} ppm)</text>)
svg << %(</svg>)

File.write(output_path, svg.join("\n") + "\n")
