require 'logger'

module Kameleon

  # This class allows access to the recipes, CLI, etc. all in the scope of
  # this environment
  class Environment

    attr_accessor :cwd
    attr_accessor :templates_dir
    attr_accessor :recipes_dir

    attr_writer :ui

    # Hash element of all recipes available
    attr_accessor :recipes

    # Hash element of all templates available
    attr_accessor :templates

    def initialize(options = {})
      # symbolify commandline options
      options = options.inject({}) {|result,(key,value)| result.update({key.to_sym => value})}
      cwd = options[:cwd] || Kameleon::Environment.workdir
      defaults = {
        :cwd => cwd,
        :templates_dir => File.expand_path(File.join(File.dirname(__FILE__), "..", "..", 'templates')),
        :recipes_dir => File.join(cwd, "recipes"),
        :tmp_dir => File.join(cwd, "tmp")
      }

      options = defaults.merge(options)
      logger.info("environment") { "Environment initialized (#{self})" }
      # Injecting all variables of the options and assign the variables
      options.each do |key, value|
        instance_variable_set("@#{key}".to_sym, options[key])
        logger.info("environment") { " - #{key} : #{options[key]}" }
      end

      # Definitions
      @recipes = nil
      @templates = nil

      return self
    end

    def self.workdir
      ENV['KAMELEON_DIR'] || Dir.pwd
    end

    def ui
      @ui ||= UI.new(self)
    end

    def cli(*args)
      CLI.start(args.flatten, :env => self)
    end

    def resource
      "kameleon"
    end

    # Accesses the logger for Veewee. This logger is a _detailed_
    # logger which should be used to log internals only. For outward
    # facing information, use {#ui}.
    #
    # @return [Logger]
    def logger
      return @logger if @logger

      output = nil
      loglevel = Logger::ERROR

      # Figure out where the output should go to.
      if ENV["KAMELEON_LOG"]
        output = STDOUT
        loglevel = Logger.const_get(ENV["KAMELEON_LOG"].upcase)
      end

        # Create the logger and custom formatter
      @logger = ::Logger.new(output)
      @logger.level = loglevel
      @logger.formatter = Proc.new do |severity, datetime, progname, msg|
        "#{datetime} - #{progname} - [#{resource}] #{msg}\n"
      end
      @logger
    end

  end
end
