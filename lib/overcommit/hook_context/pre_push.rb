# frozen_string_literal: true

module Overcommit::HookContext
  # Contains helpers related to contextual information used by pre-push hooks.
  class PrePush < Base
    attr_accessor :args

    def remote_name
      @args[0]
    end

    def remote_url
      @args[1]
    end

    def remote_ref_deletion?
      return @remote_ref_deletion if defined?(@remote_ref_deletion)

      @remote_ref_deletion ||= input_lines.
                               first.
                               split(' ').
                               first == '(deleted)'
    end

    def pushed_refs
      input_lines.map do |line|
        PushedRef.new(*line.split(' '), remote_name)
      end
    end

    def modified_files
      @modified_files ||= pushed_refs.map(&:modified_files).flatten.uniq
    end

    def modified_lines_in_file(file)
      @modified_lines ||= {}
      @modified_lines[file] = pushed_refs.each_with_object(Set.new) do |pushed_ref, set|
        set.merge(pushed_ref.modified_lines_in_file(file))
      end
    end

    PushedRef = Struct.new(:local_ref, :local_sha1, :remote_ref, :remote_sha1, :remote_name) do
      def forced?
        !(created? || deleted? || overwritten_commits.empty?)
      end

      def created?
        remote_sha1 == '0' * 40
      end

      def deleted?
        local_sha1 == '0' * 40
      end

      def destructive?
        deleted? || forced?
      end

      def modified_files
        Overcommit::GitRepo.modified_files(refs: ref_range)
      end

      def modified_lines_in_file(file)
        Overcommit::GitRepo.extract_modified_lines(file, refs: ref_range)
      end

      def to_s
        "#{local_ref} #{local_sha1} #{remote_ref} #{remote_sha1}"
      end

      private

      def ref_range
        # If the remote or local ref is "0000000....", we can't compare to get
        # the contents of the push. For the common scenario of pushing a new
        # branch to make a PR and eventually merge to master, we can compare
        # and find the point where this branch diverged. This may not give the
        # best result in every case, but at least the hook should run.
        merge_target = "#{remote_name}/master"
        branch_target = created? ? local_sha1 : remote_sha1
        base = `git merge-base #{merge_target} #{branch_target}`.chomp

        if created?
          "#{base}..#{local_sha1}"
        elsif deleted?
          "#{remote_sha1}..#{base}"
        else
          "#{remote_sha1}..#{local_sha1}"
        end
      end

      def overwritten_commits
        return @overwritten_commits if defined? @overwritten_commits
        result = Overcommit::Subprocess.spawn(%W[git rev-list #{remote_sha1} ^#{local_sha1}])
        if result.success?
          result.stdout.split("\n")
        else
          raise Overcommit::Exceptions::GitRevListError,
                "Unable to check if commits on the remote ref will be overwritten: #{result.stderr}"
        end
      end
    end
  end
end
