# frozen_string_literal: true

require "open3"
require "shellwords"

module Forge
  module Tools
    class ReadFile < Base
      # Default page size so huge configs (~/.bashrc) do not flood the agent context.
      DEFAULT_LIMIT = 200

      def name = "read_file"
      def description = "Read a file with line numbers. Prefer search_files for keyword lookups in large files (e.g. aliases in ~/.bashrc). Paths: workspace-relative, absolute, or ~/..."
      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "File path (workspace-relative, absolute, or ~/...)" },
            offset: { type: "integer", description: "Line number to start reading from (1-based, default 1)" },
            limit: { type: "integer", description: "Max lines to return (default #{DEFAULT_LIMIT}; raise for more)" }
          },
          required: ["path"]
        }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"])
        raise ToolError, "Not a file: #{path}" unless path.file?

        lines = path.readlines
        total = lines.size
        offset = [(args["offset"] || 1).to_i - 1, 0].max
        # Explicit limit; default page when caller omits limit.
        limit = args.key?("limit") ? args["limit"]&.to_i : DEFAULT_LIMIT
        limit = DEFAULT_LIMIT if limit.nil? || limit <= 0

        selected = lines[offset, limit] || []
        numbered = selected.each_with_index.map { |l, i| "#{offset + i + 1}|#{l}" }.join
        end_line = offset + selected.size
        header = "file=#{path} lines=#{total} showing=#{offset + 1}-#{end_line}"
        if end_line < total
          header += " (truncated; use offset=#{end_line + 1} or search_files for the rest)"
        end

        Result.new(output: "#{header}\n#{numbered}")
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
        path = resolve_path(args["path"], write: true)
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
        path = resolve_path(args["path"], write: true)
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

    class FileInfo < Base
      def name = "file_info"
      def description = "Return type, size, line count, modification time, and symlink status for a workspace file."
      def parameters
        { type: "object", properties: { path: { type: "string" } }, required: ["path"] }
      end

      protected

      def execute(args)
        path = resolve_path(args["path"])
        raise ToolError, "Path does not exist: #{path}" unless path.exist?
        lines = path.file? ? path.each_line.count : nil
        Result.new(output: JSON.generate({ path: path.to_s, type: path.directory? ? "directory" : "file",
                                           size: path.file? ? path.size : nil, lines: lines,
                                           modified_at: path.mtime.utc.iso8601, symlink: path.symlink? }))
      end
    end

    class FindFiles < Base
      def name = "find_files"
      def description = "Find workspace files by basename glob without traversing common generated directories."
      def parameters
        { type: "object", properties: { pattern: { type: "string" }, path: { type: "string" }, max_results: { type: "integer" } }, required: ["pattern"] }
      end

      protected

      def execute(args)
        root = resolve_path(args["path"] || ".")
        max = (args["max_results"] || 100).to_i
        ignored = %w[.git vendor node_modules tmp log build dist coverage .bundle]
        matches = root.glob("**/#{args['pattern']}").reject { |p| p.each_filename.any? { |part| ignored.include?(part) } }.first(max)
        Result.new(output: matches.map { |p| p.relative_path_from(@workspace.root).to_s }.join("\n").then { |s| s.empty? ? "No files found" : s })
      end
    end

    class SearchSymbols < Base
      def name = "search_symbols"
      def description = "Search common Ruby, Python, JavaScript, Go, Rust, and C symbol declarations."
      def parameters
        { type: "object", properties: { pattern: { type: "string" }, path: { type: "string" }, max_results: { type: "integer" } }, required: ["pattern"] }
      end

      protected

      def execute(args)
        pattern = args["pattern"].to_s
        regex = "(?:class|module|def|function|func|struct|enum|interface|const)\\s+(?:[A-Za-z_][\\w:]*\\s*)*#{Regexp.escape(pattern)}"
        SearchFiles.new(workspace: @workspace, sandbox: @sandbox, audit: @audit).call("pattern" => regex, "path" => args["path"] || ".", "glob" => args["glob"])
      end
    end

    class ApplyPatch < Base
      def name = "apply_patch"
      def description = "Apply a validated unified diff to files inside the workspace."
      def parameters
        { type: "object", properties: { patch: { type: "string" } }, required: ["patch"] }
      end

      protected

      def execute(args)
        patch = args["patch"].to_s
        paths = patch.lines.filter_map { |line| match = line.match(/^\+\+\+ b\/(.+)$/); match && match[1].strip }
        raise ToolError, "Patch contains no target files" if paths.empty?
        paths.each { |path| resolve_path(path, write: true) }
        check = Open3.capture3("patch", "-p1", "--batch", "--dry-run", stdin_data: patch, chdir: @workspace.root.to_s)
        raise ToolError, "Patch check failed: #{check[1].strip}" unless check[2].success?
        result = Open3.capture3("patch", "-p1", "--batch", stdin_data: patch, chdir: @workspace.root.to_s)
        raise ToolError, "Patch failed: #{result[1].strip}" unless result[2].success?
        Result.new(output: "Applied patch to #{paths.join(', ')}")
      end
    end

    class SearchFiles < Base
      def name = "search_files"
      def description = "Search file contents with ripgrep/grep (regex). Best for finding aliases, hosts, config keys. Path may be a file or directory (workspace-relative, absolute, or ~/..., e.g. path=~/.bashrc pattern=podman9)."
      def parameters
        {
          type: "object",
          properties: {
            pattern: { type: "string", description: "Search pattern (regex)" },
            path: { type: "string", description: "Directory or file to search (default: workspace root). Examples: ~/.bashrc, ~/.ssh/config" },
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

        stdout, stderr, status = if rg_available?
                                   argv = ["rg", "-n", "--color=never", pattern, search_path.to_s]
                                   argv += ["-g", glob] if glob
                                   Open3.capture3(*argv)
                                 else
                                   Open3.capture3("grep", "-rn", pattern, search_path.to_s)
                                 end

        output = [stdout, stderr].reject(&:empty?).join("\n")
        exit_code = status&.exitstatus
        success = exit_code.nil? ? false : exit_code <= 1

        Result.new(
          output: output.empty? ? "No matches found" : output,
          success: success,
          error: (success ? nil : "search failed (exit #{exit_code})")
        )
      end

      def rg_available?
        @rg_available = system("which rg > /dev/null 2>&1") if @rg_available.nil?
        @rg_available
      end
    end
  end
end
