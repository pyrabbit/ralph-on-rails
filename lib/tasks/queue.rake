# frozen_string_literal: true

namespace :queue do
  desc "Show queue statistics"
  task stats: :environment do
    puts "\n=== Queue Statistics ==="
    puts

    # Get counts by queue name
    queues = %w[critical high default low]
    queues.each do |queue_name|
      count = SolidQueue::Job.where(queue_name: queue_name).pending.count
      puts "#{queue_name.ljust(12)} #{count} pending jobs"
    end

    puts
    puts "Total pending:  #{SolidQueue::Job.pending.count}"
    puts "Total running:  #{SolidQueue::Job.running.count}"
    puts "Total failed:   #{SolidQueue::FailedExecution.count}"
    puts
  end

  desc "Show pending jobs by type"
  task by_type: :environment do
    puts "\n=== Pending Jobs by Type ==="
    puts

    jobs = SolidQueue::Job.pending.group(:class_name).count
    jobs.sort_by { |_, count| -count }.each do |class_name, count|
      puts "#{class_name.ljust(40)} #{count}"
    end
    puts
  end

  desc "Show next jobs to be processed"
  task next: :environment do
    puts "\n=== Next Jobs (by queue priority) ==="
    puts

    %w[critical high default low].each do |queue_name|
      jobs = SolidQueue::Job.where(queue_name: queue_name).pending.limit(3)
      next if jobs.empty?

      puts "#{queue_name.upcase}:"
      jobs.each do |job|
        args = JSON.parse(job.arguments) rescue {}
        task_type = args.dig("arguments", 0, "task_type") || "unknown"
        queue = args.dig("arguments", 0, "queue") || queue_name

        puts "  - #{job.class_name} (#{task_type}, queue #{queue})"
      end
      puts
    end
  end

  desc "Clear failed jobs older than N days (default: 7)"
  task :clear_failed, [:days] => :environment do |_t, args|
    days = (args[:days] || 7).to_i
    cutoff = days.days.ago

    count = SolidQueue::FailedExecution.where("created_at < ?", cutoff).count
    puts "Clearing #{count} failed jobs older than #{days} days..."

    SolidQueue::FailedExecution.where("created_at < ?", cutoff).destroy_all
    puts "Done!"
  end

  desc "Retry all failed jobs"
  task retry_failed: :environment do
    failed = SolidQueue::FailedExecution.all
    puts "Retrying #{failed.count} failed jobs..."

    failed.each do |failed_job|
      failed_job.retry
    end

    puts "Done! Jobs have been re-enqueued."
  end
end
