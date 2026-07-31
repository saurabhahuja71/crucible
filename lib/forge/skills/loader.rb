# frozen_string_literal: true

module Forge
  module Skills
    class Loader
      SKILL_DIRS = [
        DATA_DIR.join("skills"),
        Pathname(Dir.pwd).join(".forge", "skills")
      ].freeze

      def self.load_all(tool_deps)
        skills = []
        SKILL_DIRS.each do |dir|
          next unless dir.exist?

          dir.glob("**/*.rb").each do |file|
            skills << load_skill(file, tool_deps)
          end
        end
        skills.compact
      end

      def self.load_skill(path, tool_deps)
        skill_module = Module.new
        skill_module.module_eval(File.read(path), path.to_s)
        if skill_module.const_defined?(:Skill)
          skill_module.const_get(:Skill).new(**tool_deps)
        end
      rescue StandardError => e
        Forge.logger.warn("Failed to load skill #{path}: #{e.message}")
        nil
      end
    end

    # Example skill structure:
    #
    # class Skill < Forge::Tools::Base
    #   def name = "my_skill"
    #   ...
    # end
  end
end
