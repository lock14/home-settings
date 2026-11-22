# frozen_string_literal: true

# Solarized Dark syntax preview for Ruby 3.3+.
# Demonstrates modules, mixins, structural pattern matching (case/in), symbols, and blocks.

require "json"
require "time"

module Telemetry
  DEFAULT_CAPACITY = 1024
  FLUSH_TIMEOUT_MS = 5_000
  HEADER_MAGIC = 0xCAFE_BABE

  module Loggable
    def format_tag(label)
      "[#{self.class.name}:#{label}]"
    end
  end

  class BaseCollector
    attr_reader :capacity

    def initialize(capacity = DEFAULT_CAPACITY)
      @capacity = capacity
    end

    def reset!
      @capacity = DEFAULT_CAPACITY
    end
  end

  class TelemetryCollector < BaseCollector
    include Enumerable
    extend Loggable

    attr_reader :endpoint, :active_count

    @@collector_instances = 0

    def initialize(endpoint, capacity: DEFAULT_CAPACITY)
      super(capacity)
      raise ArgumentError, "Endpoint must not be empty" if endpoint.nil? || endpoint.empty?

      @endpoint = endpoint
      @active_count = 0
      @events = []
      @@collector_instances += 1
    end

    def self.instance_count
      @@collector_instances
    end

    def each(&block)
      return enum_for(:each) unless block_given?

      @events.each(&block)
    end

    def classify_event(event)
      case event
      in { type: :metric, name: String => metric_name, value: (100.0..) => reading }
        "OUTLIER[#{metric_name}]=#{reading} on #{@endpoint}"
      in { type: :metric, name: String => metric_name, value: Numeric => reading } if reading >= 0.0
        "Metric[#{metric_name}]=#{reading} on #{@endpoint}"
      in { type: :heartbeat, node_id: String => node }
        "Heartbeat from #{node}"
      else
        when_fallback(event)
      end
    end

    def when_fallback(event)
      case event[:status]
      when :ok, :healthy
        "Status nominal"
      when :degraded, :critical
        "Status degraded on #{self}"
      else
        "Unknown telemetry payload"
      end
    end

    def flush_batch(batch, scale_factor: 1.0)
      return 0 if batch.nil? || batch.empty?

      processed = 0
      begin
        valid_items = batch.select do |item|
          !item.nil? && item[:type] != :ignored
        end

        valid_items.each do |item|
          break if processed >= @capacity

          summary = classify_event(item)
          next if summary.empty?

          @events << item
          processed += 1
        end

        @active_count += processed
        (processed * scale_factor).to_i
      rescue StandardError => e
        raise "Flush failed on #{@endpoint}: #{e.message}"
      ensure
        @active_count = 0 if @active_count.negative?
      end
    end
  end
end
