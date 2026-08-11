# frozen_string_literal: true

module Forge
  module Tools
    module Builtin
      def self.all(workspace:, sandbox:, audit: nil, ssh_manager: nil)
        deps = { workspace: workspace, sandbox: sandbox, audit: audit, ssh_manager: ssh_manager }
        [
          ReadFile.new(**deps),
          WriteFile.new(**deps),
          EditFile.new(**deps),
          ListDirectory.new(**deps),
          FileInfo.new(**deps),
          FindFiles.new(**deps),
          SearchFiles.new(**deps),
          SearchSymbols.new(**deps),
          ApplyPatch.new(**deps),
          ShellExecute.new(**deps),
          RunTests.new(**deps),
          GitStatus.new(**deps),
          GitDiff.new(**deps),
          GitLog.new(**deps),
          GitShow.new(**deps),
          GitBranch.new(**deps),
          AddTodo.new(**deps),
          CompleteTodo.new(**deps),
          UpdateTodo.new(**deps),
          ListTodos.new(**deps),
          HttpRequest.new(**deps)
        ]
      end
    end
  end
end
