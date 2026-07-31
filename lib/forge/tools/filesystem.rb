# frozen_string_literal: true

module Forge
  module Tools
    class ReadFile < Base
      def name = "read_file"
      def description = "Read contents of a file. Optionally specify offset and limit for large files."
      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "File path relative to workspace" },
            offset: { type: "integer", description: "Line number to start reading from (1-based)" },
            limit: { type: "integer", description: "Maximum number of lines to read" }
          },
          required: ["path"]
        }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"])
        raise ToolError, "Not a file: #{path}" unless path.file?

        lines = path.readlines
        offset = [(args["offset"] || 1).to_i - 1, 0].max
        limit = args["limit"]&.to_i

        selected = limit ? lines[offset, limit] : lines[offset..]
        numbered = selected.each_with_index.map { |l, i| "#{offset + i + 1}|#{l}" }.join

        Result.new(output: numbered)
      end
    end

    class WriteFile < Base
      def name = "write_file"
      def description = "Write content to a file, creating parent directories if needed."
      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "File path relative to workspace" },
            content: { type: "string", description: "Content to write" }
          },
          required: %w[path content]
        }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"])
        @sandbox.validate_path_access!(path)
        path.parent.mkpath
        path.write(args["content"])
        Result.new(output: "Wrote #{path} (#{args['content'].bytesize} bytes)")
      end
    end

    class EditFile < Base
      def name = "edit_file"
      def description = "Surgically replace a unique string in a file with new content."
      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "File path relative to workspace" },
            old_string: { type: "string", description: "Exact string to find (must be unique)" },
            new_string: { type: "string", description: "Replacement string" }
          },
          required: %w[path old_string new_string]
        }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"])
        raise ToolError, "Not a file: #{path}" unless path.file?

        content = path.read
        old_str = args["old_string"]
        new_str = args["new_string"]

        count = content.scan(old_str).size
        raise ToolError, "old_string not found in #{path}" if count.zero?
        raise ToolError, "old_string matches #{count} times; must be unique" if count > 1

        path.write(content.sub(old_str, new_str))
        Result.new(output: "Edited #{path}")
      end
    end

    class ListDirectory < Base
      def name = "list_directory"
      def description = "List files and directories in a path."
      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "Directory path (default: workspace root)" },
            recursive: { type: "boolean", description: "List recursively" }
          }
        }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"] || ".")
        raise ToolError, "Not a directory: #{path}" unless path.directory?

        entries = if args["recursive"]
                    path.glob("**/*").map { |p| p.relative_path_from(path).to_s }
                  else
                    path.children.map { |p| "#{p.directory? ? 'd' : 'f'} #{p.basename}" }
                  end

        Result.new(output: entries.sort.join("\n"))
      end
    end

    class SearchFiles < Base
      def name = "search_files"
      def description = "Search file contents using ripgrep (rg) or grep fallback."
      def parameters
        {
          type: "object",
          properties: {
            pattern: { type: "string", description: "Search pattern (regex)" },
            path: { type: "string", description: "Directory or file to search" },
            glob: { type: "string", description: "File glob filter (e.g. *.rb)" }
          },
          required: ["pattern"]
        }
      end

      protected

      def execute(args)
        search_path = resolve_path(args["path"] || ".")
        pattern = args["pattern"]
        glob = args["glob"]

        cmd = if system("which rg > /dev/null 2>&1")
                parts = ["rg", "-n", "--color=never", Shellwords.escape(pattern), Shellwords.escape(search_path.to_s)]
                parts += ["-g", Shellwords.escape(glob)] if glob
                parts.join(" ")
              else
                "grep -rn #{Shellwords.escape(pattern)} #{Shellwords.escape(search_path.to_s)}"
              end

        output = `#{cmd} 2>&1`
        exit_code = $CHILD_STATUS.exitstatus
        Result.new(output: output.empty? ? "No matches found" : output, success: exit_code <= 1)
      end
    end
  end
end

require "shellwords"
