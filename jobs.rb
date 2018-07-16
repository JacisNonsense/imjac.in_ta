require 'thread'
require 'array_queue'

class Job
    attr_accessor :name
    attr_accessor :delay
    attr_accessor :submit_time
    attr_accessor :immediate

    def initialize name, delay=0, recurring=false, &block
        @action = block
        @cancelled = false
        @name = name
        @delay = delay
        @recurring = recurring
        @immediate = false
    end

    def cancel
        @cancelled = true
    end

    def cancelled?
        @cancelled
    end

    def recurring?
        @recurring
    end

    def run
        @action.call() unless @cancelled
    end
end

class Jobs
    WORKER_COUNT = 4
    @jobs = []
    @jobs_mtx = Mutex.new
    @curr_jobs = []
    @curr_mtx = Mutex.new

    def self.jobs
        @jobs
    end

    def self.current_jobs
        @curr_jobs
    end

    def self.submit job
        puts "[JOBS] Submitting #{job.name}"
        job.submit_time = Time.now
        @jobs_mtx.synchronize {
            @jobs << job
        }
    end

    def self.pull job
        puts "[JOBS] Pulling #{job.name}"
        @jobs_mtx.synchronize {
            @jobs.delete(job)
        }
    end

    def self.start
        @workers = (0...WORKER_COUNT).map do |threadnum|
            Thread.new do
                while true
                    begin
                        job = nil
                        @jobs_mtx.synchronize {
                            job = @jobs.find { |job| Time.now >= (job.submit_time + job.delay) || job.immediate }
                            @jobs.reject! { |x| x == job }
                        }
                        unless job.nil? || job.cancelled?
                            puts "[JOB WORK ##{threadnum}] Running job #{job.name}..."
                            @curr_mtx.synchronize { @curr_jobs[threadnum] = job }
                            job.run
                            if job.recurring?
                                puts "[JOB WORK ##{threadnum}] Resubmitting recurring job #{job.name}"
                                job.submit_time = Time.now
                                job.immediate = false
                                @jobs_mtx.synchronize {
                                    @jobs << job
                                }
                            end
                            puts "[JOB WORK ##{threadnum}] Finished job #{job.name}!"
                            @curr_mtx.synchronize { @curr_jobs[threadnum] = nil }
                        end
                        sleep 1
                    rescue => e
                        puts "[JOB WORK ##{threadnum}] Error: #{e}"
                        puts e.backtrace.map { |x| "[JOB WORK ##{threadnum}]!\t #{x}" }
                        sleep 1
                    end
                end
            end
        end
    end
end