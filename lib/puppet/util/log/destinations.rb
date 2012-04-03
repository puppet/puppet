Puppet::Util::Log.newdesttype :syslog do
  def self.suitable?(obj)
    Puppet.features.syslog?
  end

  def close
    Syslog.close
  end

  def initialize
    Syslog.close if Syslog.opened?
    name = Puppet[:name]
    name = "puppet-#{name}" unless name =~ /puppet/

    options = Syslog::LOG_PID | Syslog::LOG_NDELAY

    # XXX This should really be configurable.
    str = Puppet[:syslogfacility]
    begin
      facility = Syslog.const_get("LOG_#{str.upcase}")
    rescue NameError
      raise Puppet::Error, "Invalid syslog facility #{str}"
    end

    @syslog = Syslog.open(name, options, facility)
  end

  def handle(msg)
    # XXX Syslog currently has a bug that makes it so you
    # cannot log a message with a '%' in it.  So, we get rid
    # of them.
    if msg.source == "Puppet"
      msg.to_s.split("\n").each do |line|
        @syslog.send(msg.level, line.gsub("%", '%%'))
      end
    else
      msg.to_s.split("\n").each do |line|
        @syslog.send(msg.level, "(%s) %s" % [msg.source.to_s.gsub("%", ""),
            line.gsub("%", '%%')
          ]
        )
      end
    end
  end
end

Puppet::Util::Log.newdesttype :file do
  require 'fileutils'

  def self.match?(obj)
    Puppet::Util.absolute_path?(obj)
  end

  def close
    if defined?(@file)
      @file.close
      @file = nil
    end
  end

  def flush
    @file.flush if defined?(@file)
  end

  attr_accessor :autoflush

  def initialize(path)
    @name = path
    # first make sure the directory exists
    # We can't just use 'Config.use' here, because they've
    # specified a "special" destination.
    unless FileTest.exist?(File.dirname(path))
      FileUtils.mkdir_p(File.dirname(path), :mode => 0755)
      Puppet.info "Creating log directory #{File.dirname(path)}"
    end

    # create the log file, if it doesn't already exist
    file = File.open(path, File::WRONLY|File::CREAT|File::APPEND)

    @file = file

    @autoflush = Puppet[:autoflush]
  end

  def handle(msg)
    @file.puts("#{msg.time} #{msg.source} (#{msg.level}): #{msg}")

    @file.flush if @autoflush
  end
end

Puppet::Util::Log.newdesttype :console do
  require 'puppet/util/colors'
  include Puppet::Util::Colors

  def initialize()
    # This is somewhat of a hack.  There is some code in Logging that will attempt to
    #  open a logging destination, and if it fails, it will attempt to fall back to
    #  creating a :console log.  However, if we're in daemon mode we have already
    #  closed off stdout/stderr by that point in time... so, here we do a check
    #  to see if it looks like stdout has been closed off:
    if ($stdout.is_a?(File) && $stdout.path == "/dev/null")
      # if it has, we are probably in a pretty bad state and most likely just need
      #  to log some failure message to somewhere where we hope someone has a prayer
      #  of seeing it, so let's use STDERR.
      @out = STDERR
    else
      # otherwise we are most likely just in normal console mode, so we'll direct
      #  our output to $stdout as we have always done in the past.
      @out = $stdout
    end

    # Flush output immediately.
    @out.sync = true
  end

  def handle(msg)
    if msg.source == "Puppet"
      @out.puts colorize(msg.level, "#{msg.level}: #{msg}")
    else
      @out.puts colorize(msg.level, "#{msg.level}: #{msg.source}: #{msg}")
    end
  end
end

Puppet::Util::Log.newdesttype :telly_prototype_console do
  require 'puppet/util/colors'
  include Puppet::Util::Colors

  def initialize
    # Flush output immediately.
    $stderr.sync = true
    $stdout.sync = true
  end

  def handle(msg)
    error_levels = {
      :warning => 'Warning',
      :err     => 'Error',
      :alert   => 'Alert',
      :emerg   => 'Emergency',
      :crit    => 'Critical'
    }

    str = msg.respond_to?(:multiline) ? msg.multiline : msg.to_s

    case msg.level
    when *error_levels.keys
      $stderr.puts colorize(:hred, "#{error_levels[msg.level]}: #{str}")
    when :info
      $stdout.puts "#{colorize(:green, 'Info')}: #{str}"
    when :debug
      $stdout.puts "#{colorize(:cyan, 'Debug')}: #{str}"
    else
      $stdout.puts str
    end
  end
end

Puppet::Util::Log.newdesttype :host do
  def initialize(host)
    Puppet.info "Treating #{host} as a hostname"
    args = {}
    if host =~ /:(\d+)/
      args[:Port] = $1
      args[:Server] = host.sub(/:\d+/, '')
    else
      args[:Server] = host
    end

    @name = host

    @driver = Puppet::Network::Client::LogClient.new(args)
  end

  def handle(msg)
    unless msg.is_a?(String) or msg.remote
      @hostname ||= Facter["hostname"].value
      unless defined?(@domain)
        @domain = Facter["domain"].value
        @hostname += ".#{@domain}" if @domain
      end
      if Puppet::Util.absolute_path?(msg.source)
        msg.source = @hostname + ":#{msg.source}"
      elsif msg.source == "Puppet"
        msg.source = @hostname + " #{msg.source}"
      else
        msg.source = @hostname + " #{msg.source}"
      end
      begin
        #puts "would have sent #{msg}"
        #puts "would have sent %s" %
        #    CGI.escape(YAML.dump(msg))
        begin
          tmp = CGI.escape(YAML.dump(msg))
        rescue => detail
          puts "Could not dump: #{detail}"
          return
        end
        # Add the hostname to the source
        @driver.addlog(tmp)
      rescue => detail
        Puppet.log_exception(detail)
        Puppet::Util::Log.close(self)
      end
    end
  end
end

# Log to a transaction report.
Puppet::Util::Log.newdesttype :report do
  attr_reader :report

  match "Puppet::Transaction::Report"

  def initialize(report)
    @report = report
  end

  def handle(msg)
    @report << msg
  end
end

# Log to an array, just for testing.
module Puppet::Test
  class LogCollector
    def initialize(logs)
      @logs = logs
    end

    def <<(value)
      @logs << value
    end
  end
end

Puppet::Util::Log.newdesttype :array do
  match "Puppet::Test::LogCollector"

  def initialize(messages)
    @messages = messages
  end

  def handle(msg)
    @messages << msg
  end
end

