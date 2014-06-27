require 'kameleon/engine'
require 'kameleon/recipe'
require 'kameleon/utils'

module Kameleon
  class CLI < Thor
    include Thor::Actions

    class_option :color, :type => :boolean, :default => true,
                 :desc => "Enable colorization in output"
    class_option :debug, :type => :boolean, :default => false,
                 :desc => "Enable debug output"
    map %w(-h --help) => :help

    method_option :force,:type => :boolean,
                  :default => false, :aliases => "-f",
                  :desc => "Overwrite all existing files"
    desc "import [TEMPLATE_NAME]", "Imports the given template"
    def import(template_name)
      templates_path = Kameleon.env.templates_path
      template_path = File.join(templates_path, template_name) + '.yaml'
      begin
        tpl = RecipeTemplate.new(template_path, :strict => false)
      rescue
        raise TemplateNotFound, "Template '#{template_name}' not found. " \
                                "To see all templates, run the command "\
                                "`kameleon templates`"
      else
        files2copy = tpl.base_recipes_files + tpl.files
        files2copy.each do |path|
          relative_path = path.relative_path_from(Kameleon.env.templates_path)
          dst = File.join(Kameleon.env.workspace, relative_path)
          copy_file(path, dst)
        end
      end
    end

    method_option :force,:type => :boolean,
                  :default => false, :aliases => "-f",
                  :desc => "Overwrite all existing files"
    desc "new [RECIPE_NAME] [TEMPLATE_NAME]", "Creates a new recipe"
    def new(recipe_name, template_name)
      if recipe_name == template_name
        fail RecipeError, "Recipe name should be different from template name"
      end
      templates_path = Kameleon.env.templates_path
      template_path = File.join(templates_path, template_name) + '.yaml'
      begin
        tpl = RecipeTemplate.new(template_path, :strict => false)
      rescue
        raise TemplateNotFound, "Template '#{template_name}' not found. " \
                                "To see all templates, run the command "\
                                "`kameleon templates`"
      else
        files2copy = tpl.base_recipes_files + tpl.files
        files2copy.each do |path|
          relative_path = path.relative_path_from(Kameleon.env.templates_path)
          dst = File.join(Kameleon.env.workspace, relative_path)
          copy_file(path, dst)
        end
        Dir::mktmpdir do |tmp_dir|
          recipe_path = File.join(tmp_dir, recipe_name + '.yaml')
          ## copying recipe
          File.open(recipe_path, 'w+') do |file|
            extend_erb_tpl = File.join(Kameleon.env.templates_path, "extend.erb")
            erb = ERB.new(File.open(extend_erb_tpl, 'rb') { |f| f.read })
            result = erb.result(binding)
            file.write(result)
          end
          recipe_dst = File.join(Kameleon.env.workspace, recipe_name + '.yaml')
          copy_file(recipe_path, Pathname.new(recipe_dst))
        end
        # template_recipe.copy_extended_recipe(recipe_name, options[:force])
      end
    end

    desc "templates", "Lists all defined templates"
    def templates
      puts "The following templates are available in " \
                 "#{ Kameleon.templates_path }:"
      templates_hash = []
      templates_path = File.join(Kameleon.env.templates_path, "/")
      all_yaml_files = Dir["#{templates_path}**/*.yaml"]
      steps_files = Dir["#{templates_path}steps/**/*.yaml"]
      templates_files = all_yaml_files - steps_files
      templates_files.each do |f|
        begin
        recipe = RecipeTemplate.new(f, :strict => false)
        templates_hash.push({
          "name" => f.gsub(templates_path, "").chomp(".yaml"),
          "description" => recipe.metainfo['description'],
        })
        rescue => e
          raise e if Kameleon.env.debug
        end
      end
      templates_hash = templates_hash.sort_by{ |k| k["name"] }
      tp templates_hash, {"name" => {:width => 30}}, { "description" => {:width => 60}}
    end

    desc "version", "Prints the Kameleon's version information"
    def version
      puts "Kameleon version #{Kameleon::VERSION}"
    end
    map %w(-v --version) => :version

    desc "build [RECIPE_PATH]", "Builds the appliance from the given recipe"
    method_option :build_path, :type => :string ,
                  :default => nil, :aliases => "-b",
                  :desc => "Set the build directory path"
    method_option :clean, :type => :boolean ,
                  :default => false,
                  :desc => "Run the command `kameleon clean` first"
    method_option :from_checkpoint, :type => :string ,
                  :default => nil,
                  :desc => "Using specific checkpoint to build the image. " \
                           "Default value is the last checkpoint."
    method_option :checkpoint, :type => :boolean ,
                  :default => true,
                  :desc => "Do not use checkpoints"
    method_option :cache, :type => :boolean,
                  :default => false,
                  :desc => "Generate a persistent cache for the appliance."
    method_option :from_cache, :type => :string ,
                  :default => nil,
                  :desc => "Using a persistent cache tar file to build the image."
    method_option :proxy_path, :type => :string ,
                  :default => nil,
                  :desc => "Full path of the proxy binary to use for the persistent cache."

    def build(recipe_path=nil)
      if recipe_path== nil then
        Kameleon.ui.info("Using the cached recipe")
        @cache = Kameleon::Persistent_cache.instance
        @cache.cache_path = options[:from_cache]
        recipe_path =  @cache.get_recipe
      end
      clean(recipe_path) if options[:clean]
      engine = Kameleon::Engine.new(Recipe.new(recipe_path), options)
      Kameleon.ui.info("Starting build recipe '#{recipe_path}'")
      start_time = Time.now.to_i
      engine.build
      total_time = Time.now.to_i - start_time
      Kameleon.ui.info("")
      Kameleon.ui.info("Build recipe '#{recipe_path}' is completed !")
      Kameleon.ui.info("Build total duration : #{total_time} secs")
      Kameleon.ui.info("Build directory : #{engine.cwd}")
    end

    desc "checkpoints [RECIPE_PATH]", "Lists all availables checkpoints"
    method_option :build_path, :type => :string ,
                  :default => nil, :aliases => "-b",
                  :desc => "Set the build directory path"
    def checkpoints(recipe_path)
      engine = Kameleon::Engine.new(Recipe.new(recipe_path), options)
      engine.pretty_checkpoints_list
    end

    desc "clean [RECIPE_PATH]", "Cleaning 'out' and 'local' contexts and removing all checkpoints"
    method_option :build_path, :type => :string ,
                  :default => nil, :aliases => "-b",
                  :desc => "Set the build directory path"
    def clean(recipe_path)
      engine = Kameleon::Engine.new(Recipe.new(recipe_path), options)
      engine.clear
    end
    map %w(clear) => :clean

    desc "commands", "Lists all available commands", :hide => true
    def commands
      puts CLI.all_commands.keys - ["commands", "completions"]
    end

    desc "source_root", "Prints the kameleon directory path", :hide => true
    def source_root
      puts Kameleon.source_root
    end

    def initialize(*args)
      super
      self.options ||= {}
      Kameleon.env = Kameleon::Environment.new(self.options)
      if !$stdout.tty? or !options["color"]
        Thor::Base.shell = Thor::Shell::Basic
      end
      Kameleon.ui = Kameleon::UI::Shell.new(self.options)
      Kameleon.ui.level = "debug" if self.options["verbose"]
    end

    def self.start(*)
      super
    rescue Exception => e
      Kameleon.ui = Kameleon::UI::Shell.new
      raise e
    end

    def self.source_root
      Kameleon.source_root
    end

  end

end
