#!/usr/bin/env ruby
#require 'aws-sdk'
require 'benchmark'

ITERATIONS = 200
PUBLISHER_THREADS = 3

class KinesisTest

  attr_reader :iterations
  attr_reader :publisher_thread_count
  attr_reader :stream_name
  attr_reader :partition_key
  attr_reader :kinesis
  attr_reader :shard_id

  def initialize(iterations, publisher_thread_count)
    @publisher_thread_count = publisher_thread_count
    # Round the iterations to a multiple of `publisher_thread_count`
    @iterations = (iterations / publisher_thread_count).ceil * publisher_thread_count
    @stream_name = 'kinesis-test-rb'
    @partition_key = 'only_one_shard'
    @kinesis = Aws::Kinesis::Client.new(region: 'us-west-2')
    @shard_id = nil
  end

  def run
    create_stream
    publish
    consume
  ensure
    delete_stream
  end

  protected

  def create_stream
    puts "Creating kinesis stream #{stream_name.inspect}"
    kinesis.create_stream(stream_name: stream_name, shard_count: 1)

    puts "Retrieving shard id from new stream"
    # When the stream is first created the shards don't exist for several
    # seconds. We wait and then, when the single shard is available, store its
    # shard_id
    @shard_id = loop do
      shards = kinesis.describe_stream(stream_name: stream_name).stream_description.shards
      if shards[0]
        break shards[0].shard_id
      else
        print '.'
        STDOUT.flush
        sleep 1
      end
    end
    puts ""
    puts "Shard id: #{shard_id}"
  end

  def delete_stream
    kinesis.delete_stream(stream_name: stream_name)
  end

  # We take advantage of the thread-safety of the AWS client library here.
  # We divide our work into threads and issue (blocking) `put_record` calls in each thread.
  # The `.map(&:join)` line is the same as `wait` in bash or C - it blocks the
  # parent thread until the child threads return.
  def publish
    benchmark = Benchmark.measure do
      publisher_thread_count.times.map do |thread_idx|
        Thread.new do
          batch_count = (iterations / publisher_thread_count).ceil
          puts "Publishing #{batch_count} records on thread #{thread_idx + 1}/#{publisher_thread_count}"
          batch_count.times do |n|
            kinesis.put_record(stream_name: stream_name, partition_key: partition_key, data: "this is message #{thread_idx}/#{n}") 
          end
        end
      end.map(&:join)
    end
    puts "published #{iterations} records in #{"%0.2f" % benchmark.real} seconds"
  end

  # Reads all records from the single shard of this stream
  # The iterator uses the TRIM_HORIZON type which starts at the beginning of
  # available history and works up to the most current record.
  # Unlike the publish step this is all performed synchronously in a single
  # thread (because the get_records() call returns a batch of records and is
  # therefore far faster)
  def consume
    shard_iterator = kinesis.get_shard_iterator(stream_name: stream_name, shard_id: shard_id, shard_iterator_type: 'TRIM_HORIZON').shard_iterator

    consumed_count = 0
    puts "starting consumption of #{iterations} records"
    benchmark = Benchmark.measure do
      while (result = kinesis.get_records(shard_iterator: shard_iterator)) && result.records.any?
        shard_iterator = result.next_shard_iterator
        consumed_count += result.records.size
      end
    end
    puts "consumed #{consumed_count} records in #{"%0.2f" % benchmark.real} seconds"
  end
end

KinesisTest.new(ITERATIONS, PUBLISHER_THREADS).run
