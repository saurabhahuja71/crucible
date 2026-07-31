# frozen_string_literal: true

# Example Forge skill — copy to ~/.local/share/forge/skills/ or .forge/skills/
class Skill < Forge::Tools::Base
  def name = "project_info"
  def description = "Return basic information about the current workspace"
  def parameters
    { type: "object", properties: {} }
  end

  protected

  def execute(_args)
    info = {
      root: @workspace.root.to_s,
      trusted: @workspace.trusted,
      files: Dir.glob(@workspace.root.join("**", "*")).count { |f| File.file?(f) }
    }
    Forge::Tools::Result.new(output: JSON.pretty_generate(info))
  end
end
