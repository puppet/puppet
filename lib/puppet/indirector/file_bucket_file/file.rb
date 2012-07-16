require 'puppet/indirector/code'
require 'puppet/file_bucket/file'
require 'puppet/util/checksums'
require 'puppet/util/diff'
require 'fileutils'
require 'pathname'
require 'time'

module Puppet::FileBucketFile
  class File < Puppet::Indirector::Code
    include Puppet::Util::Checksums

    desc "Store files in a directory set based on their checksums."

    def initialize
      Puppet.settings.use(:filebucket)
    end

    def find( request )
      if not request.options[:bucket_path]
       request.options[:bucket_path] = Puppet[:bucketdir]
      end
      if request.options[:list_all]
        return '' unless ::File.exists?(request.options[:bucket_path])
        fromdate = request.options[:fromdate] || "1-1-1970"
        todate = request.options[:todate] || Time.now.httpdate.to_s
        buck = {}
        msg = ""
        Pathname.new(request.options[:bucket_path]).find { |d|
          if d.file?
            if d.basename.to_s == "paths"
              filename = d.read.strip
              filestat = Time.parse(d.stat.mtime.to_s)
              from = Time.parse(fromdate)
              to = Time.parse(todate)
              if Time.parse(fromdate) <= filestat and filestat <= Time.parse(todate.to_s)
                if buck[filename]
                  buck[filename] += [[ d.stat.mtime , d.parent.basename ]]
                else
                  buck[filename] = [[ d.stat.mtime , d.parent.basename ]]
                end
              end
            end
          end
        }
        buck.sort.each { |f, contents|
          contents.sort.each { |d, chksum|
            date = DateTime.parse(d.to_s).strftime("%F %T")
            msg += "#{chksum} #{date} #{f}\n"
          }
        }
        return model.new(msg)
      end

      checksum, files_original_path = request_to_checksum_and_path( request )
      dir_path = path_for(request.options[:bucket_path], checksum)
      file_path = ::File.join(dir_path, 'contents')

      return nil unless ::File.exists?(file_path)
      return nil unless path_match(dir_path, files_original_path)

      if request.options[:diff_with]
        hash_protocol = sumtype(checksum)
        if request.options[:diff_with] != ''
           file2_path = path_for(request.options[:bucket_path], request.options[:diff_with], 'contents')
        else
           file2_path = filename(request.options[:bucket_path],checksum)
        end
        raise "could not find diff_with #{request.options[:diff_with]}" unless ::File.exists?(file2_path)
        return model.new(diff(file_path, file2_path))
      else
        contents = IO.binread(file_path)
        Puppet.info "FileBucket read #{checksum}"
        model.new(contents)
      end
    end

    def head(request)
      checksum, files_original_path = request_to_checksum_and_path(request)
      dir_path = path_for(request.options[:bucket_path], checksum)

      ::File.exists?(::File.join(dir_path, 'contents')) and path_match(dir_path, files_original_path)
    end

    def save( request )
      instance = request.instance
      checksum, files_original_path = request_to_checksum_and_path(request)

      save_to_disk(instance, files_original_path)
      instance.to_s
    end

    private

    def path_match(dir_path, files_original_path)
      return true unless files_original_path # if no path was provided, it's a match
      paths_path = ::File.join(dir_path, 'paths')
      return false unless ::File.exists?(paths_path)
      ::File.open(paths_path) do |f|
        f.each_line do |line|
          return true if line.chomp == files_original_path
        end
      end
      return false
    end

    def save_to_disk( bucket_file, files_original_path )
      filename = path_for(bucket_file.bucket_path, bucket_file.checksum_data, 'contents')
      dir_path = path_for(bucket_file.bucket_path, bucket_file.checksum_data)
      paths_path = ::File.join(dir_path, 'paths')

      # If the file already exists, do nothing.
      if ::File.exist?(filename)
        verify_identical_file!(bucket_file)
      else
        # Make the directories if necessary.
        unless ::File.directory?(dir_path)
          Puppet::Util.withumask(0007) do
            ::FileUtils.mkdir_p(dir_path)
          end
        end

        Puppet.info "FileBucket adding #{bucket_file.checksum}"

        # Write the file to disk.
        Puppet::Util.withumask(0007) do
          ::File.open(filename, ::File::WRONLY|::File::CREAT, 0440) do |of|
            of.binmode
            of.print bucket_file.contents
          end
          ::File.open(paths_path, ::File::WRONLY|::File::CREAT, 0640) do |of|
            # path will be written below
          end
        end
      end

      unless path_match(dir_path, files_original_path)
        ::File.open(paths_path, 'a') do |f|
          f.puts(files_original_path)
        end
      end
    end

    def request_to_checksum_and_path( request )
      checksum_type, checksum, path = request.key.split(/\//, 3)
      if path == '' # Treat "md5/<checksum>/" like "md5/<checksum>"
        path = nil
      else
        path &&= "/#{path}" # Add '/' to the filepath: split removed it
      end
      raise "Unsupported checksum type #{checksum_type.inspect}" if checksum_type != 'md5'
      raise "Invalid checksum #{checksum.inspect}" if checksum !~ /^[0-9a-f]{32}$/
      [checksum, path]
    end

    def filename(bucket_path, digest)
      paths_path = path_for(bucket_path, digest, 'paths')
      filepath = ::File.new(paths_path).read.strip
    end

    def path_for(bucket_path, digest, subfile = nil)
      bucket_path ||= Puppet[:bucketdir]

      dir     = ::File.join(digest[0..7].split(""))
      basedir = ::File.join(bucket_path, dir, digest)

      return basedir unless subfile
      ::File.join(basedir, subfile)
    end

    # If conflict_check is enabled, verify that the passed text is
    # the same as the text in our file.
    def verify_identical_file!(bucket_file)
      disk_contents = IO.binread(path_for(bucket_file.bucket_path, bucket_file.checksum_data, 'contents'))

      # If the contents don't match, then we've found a conflict.
      # Unlikely, but quite bad.
      if disk_contents != bucket_file.contents
        raise Puppet::FileBucket::BucketError, "Got passed new contents for sum #{bucket_file.checksum}"
      else
        Puppet.info "FileBucket got a duplicate file #{bucket_file.checksum}"
      end
    end
  end
end
