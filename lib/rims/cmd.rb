# -*- coding: utf-8 -*-

require 'net/imap'
require 'optparse'
require 'pp'if $DEBUG

module RIMS
  module Cmd
    CMDs = {}

    def self.command_function(method_name)
      module_function(method_name)
      method_name = method_name.to_s
      cmd_name = method_name.sub(/^cmd_/, '').gsub(/_/, '-')
      CMDs[cmd_name] = method_name.to_sym
    end

    def run_cmd(args)
      options = OptionParser.new
      if (args.empty?) then
        cmd_help(options, args)
        return 1
      end

      cmd_name = args.shift
      pp cmd_name if $DEBUG
      pp args if $DEBUG

      if (method_name = CMDs[cmd_name]) then
        options.program_name += " #{cmd_name}"
        send(method_name, options, args)
      else
        raise "unknown command: #{cmd_name}"
      end
    end
    module_function :run_cmd

    def cmd_help(options, args)
      STDERR.puts "usage: #{File.basename($0)} command options"
      STDERR.puts ""
      STDERR.puts "commands:"
      CMDs.each_key do |cmd_name|
        STDERR.puts "  #{cmd_name}"
      end
      STDERR.puts ""
      STDERR.puts "command help options:"
      STDERR.puts "  -h, --help"
      0
    end
    command_function :cmd_help

    def cmd_server(options, args)
      conf = Config.new
      conf.load(base_dir: Dir.getwd)

      options.on('-f', '--config-yaml=CONFIG_FILE') do |path|
        conf.load_config_yaml(path)
      end
      options.on('-d', '--base-dir=DIR', ) do |path|
        conf.load(base_dir: path)
      end
      options.on('--log-file=FILE') do |path|
        conf.load(log_file: path)
      end
      options.on('-l', '--log-level=LEVEL', %w[ debug info warn error fatal ]) do |level|
        conf.load(log_level: level)
      end
      options.on('--kvs-type=TYPE', %w[ gdbm ]) do |type|
        conf.load(key_value_store_type: type)
      end
      options.on('--username=NAME', String) do |name|
        conf.load(username: name)
      end
      options.on('--password=PASS') do |pass|
        conf.load(password: pass)
      end
      options.on('--ip-addr=IP_ADDR') do |ip_addr|
        conf.load(ip_addr: ip_addr)
      end
      options.on('--ip-port=PORT', Integer) do |port|
        conf.load(ip_port: port)
      end
      options.parse!(args)

      pp conf.config if $DEBUG
      conf.setup
      pp conf.config if $DEBUG

      server = RIMS::Server.new(**conf.config)
      server.start

      0
    end
    command_function :cmd_server

    def cmd_imap_append(options, args)
      opt_verbose = false
      imap_host = 'localhost'
      imap_opts = { port: 1430 }
      imap_username = nil
      imap_password = nil
      imap_mailbox = 'INBOX'

      options.on('-v', '--[no-]verbose') do |v|
        opt_verbose = v
      end
      options.on('--[no-]imap-debug') do |v|
        Net::IMAP.debug = v
      end
      options.on('-n', '--host=HOSTNAME') do |host|
        imap_host = host
      end
      options.on('-o', '--port=PORT', Integer) do |port|
        imap_opts[:port] = port
      end
      options.on('-s', '--[no-]use-ssl') do |v|
        imap_opts[:ssl] = v
      end
      options.on('-u', '--username=NAME') do |name|
        imap_username = name
      end
      options.on('-w', '--password=PASS') do |pass|
        imap_password = pass
      end
      options.on('-m', '--mailbox') do |mbox|
        imap_mailbox = mbox
      end
      options.parse!(args)

      if ($DEBUG) then
        pp imap_host
        pp imap_opts
        pp imap_username
        pp imap_password
      end

      unless (imap_username && imap_password) then
        raise 'need for username and password.'
      end

      imap = Net::IMAP.new(imap_host, imap_opts)
      begin
        if (opt_verbose) then
          puts "server greeting: #{imap_res2str(imap.greeting)}"
          puts "server capability: #{imap.capability.join(' ')}"
        end

        res = imap.login(imap_username, imap_password)
        puts "login: #{imap_res2str(res)}" if opt_verbose

        if (args.empty?) then
          res = imap.append(imap_mailbox, STDIN.read)
          puts "append: #{imap_res2str(res)}" if opt_verbose
        else
          for filename in args
            res = imap.append(imap_mailbox, IO.read(filename, mode: 'rb', encoding: 'ascii-8bit'))
            puts "append: #{imap_res2str(res)}" if opt_verbose
          end
        end
      ensure
        imap.logout
      end

      0
    end
    command_function :cmd_imap_append

    def imap_res2str(imap_response)
      "#{imap_response.name} #{imap_response.data.text}"
    end
    module_function :imap_res2str
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End: