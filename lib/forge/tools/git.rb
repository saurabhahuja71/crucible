# frozen_string_literal: true

require "shellwords"

module Forge
  module Tools
    class GitStatus < Base
      def name = "git_status"
      def description = "Show git status of the workspace."
      def parameters
        { type: "object", properties: {} }
      end

      protected

      def execute(_args)
        run_git("status --short --branch")
      end
    end

    class GitDiff < Base
      def name = "git_diff"
      def description = "Show git diff (staged or unstaged)."
      def parameters
        {
          type: "object",
          properties: {
            staged: { type: "boolean", description: "Show staged diff" },
            path: { type: "string", description: "Limit to specific path" }
          }
        }
      end

      protected

      def execute(args)
        cmd = "diff"
        cmd += " --cached" if args["staged"]
        cmd += " -- #{Shellwords.escape(args['path'])}" if args["path"]
        run_git(cmd)
      end
    end

    class GitLog < Base
      def name = "git_log"
      def description = "Show recent git commit history."
      def parameters
        {
          type: "object",
          properties: {
            count: { type: "integer", description: "Number of commits (default 10)" }
          }
        }
      end

      protected

      def execute(args)
        n = (args["count"] || 10).to_i
        run_git("log --oneline -n #{n}")
      end

      private

      def run_git(subcommand)
        output = `cd #{Shellwords.escape(@workspace.root.to_s)} && git #{subcommand} 2>&1`
        Result.new(output: output, success: $CHILD_STATUS.success?)
      end
    end

    class GitShow < Base
      def name = "git_show"
      def description = "Show a bounded Git object or commit."
      def parameters
        { type: "object", properties: { object: { type: "string" } }, required: ["object"] }
      end

      protected

      def execute(args) = run_git("show --stat --oneline --no-renames #{Shellwords.escape(args['object'])}")
    end

    class GitBranch < Base
      def name = "git_branch"
      def description = "Show the current Git branch and local branches."
      def parameters = { type: "object", properties: {} }

      protected

      def execute(_args) = run_git("branch --all --no-color")
    end
  end
end
