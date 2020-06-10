require 'webrick/httputils'
require 'dav4rack'
require 'forwardable'
require 'dav4rack/resource'

class Metis
  class WebDavResource < DAV4Rack::Resource
    extend Forwardable
    include WEBrick::HTTPUtils
    include DAV4Rack::Utils

    attr_reader :inhabitant
    def_delegators :inhabitant, :creation_date, :last_modified, :etag, :content_length, :directory?

    def inhabitant
      if @user.instance_of?(Etna::User)
        @inhabitant ||= DataResourceNode.descend(path, @user)
      else
        nil
      end
    end

    def application
      @application ||= Etna::Application.instance
    end

    def authenticate(uname, password)
      begin
        # payload, _ = application.sign.jwt_decode(password)
        payload, _ = JSON.parse(Base64.strict_decode64(password))
      rescue
        return false
      end

      @user = request.env['etna.user'] = Etna::User.new(payload.map { |k, v| [k.to_sym, v] }.to_h, password)
      true
    end

    def root
      @options[:root_uri_path]
    end

    def get(request, response)
      raise NotFound unless exist?

      unless directory?
        # Files are actually sent via apache, which swaps the body out of a response based on this header.
        response['X-Sendfile'] = inhabitant.file.data_block.location
      end

      OK
    end

    def children
      return [] unless exist?

      inhabitant.children.map do |node|
        child node.path_segment
      end
    end

    def exist?
      !inhabitant.nil?
    end

    def collection?
      directory?
    end

    def content_type
      if directory?
        "text/html"
      else
        mime_type(path, DefaultMimeTypes)
      end
    end

    protected

    def bucket_allowed?(bucket)
      true
      # bucket.allowed?(@user, @request.env['etna.hmac'])
    end

    def project
      @project ||= Project.first(project_name: project_name)
    end
  end

  class DataResourceNode
    attr_reader :parent, :path_segment, :user

    def initialize(user, parent, segment)
      @user = user
      @parent = parent
      @path_segment = segment
    end

    def self.descend(path, user)
      (path[1..-1].split('/')).inject(RootDirectoryResourceNode.new(user)) do |parent, next_child|
        parent&.find_child(next_child)
      end
    end

    def find_child(segment)
      children.find do |node|
        node.path_segment == segment
      end
    end

    def children
      []
    end

    def etag
      nil
    end

    def directory?
      true
    end

    def content_length
      0
    end

    def creation_date
      Time.now
    end

    def last_modified
      Time.now
    end
  end

  class RootDirectoryResourceNode < DataResourceNode
    def initialize(user)
      super(user, nil, nil)
    end

    def children
      project_names = Metis::Bucket.distinct.select(:project_name).map(&:project_name)
      listable_projects = project_names.select do |project_name|
        user.is_admin?(project_name) || user.permissions[project_name]
      end

      listable_projects.map { |project_name| ProjectResourceNode.new(user, self, project_name) }
    end
  end

  class ProjectResourceNode < DataResourceNode
    def creation_date
      first_created_bucket&.created_at || Time.now
    end

    def last_modified
      last_updated_bucket&.updated_at || Time.now
    end

    def children
      buckets = Metis::Bucket.where(project_name: path_segment).all
      listable_buckets = buckets.select do |bucket|
        bucket.allowed?(user, nil)
      end

      listable_buckets.map do |bucket|
        BucketResourceNode.new(user, self, bucket.name)
      end
    end

    def last_updated_bucket
      @last_updated_bucket ||= Metis::Bucket.where(project_name: path_segment).order_by(:updated_at).last
    end

    def first_created_bucket
      @first_created_bucket ||= Metis::Bucket.where(project_name: path_segment).order_by(:created_at).first
    end
  end

  class BucketResourceNode < DataResourceNode
    def creation_date
      first_created_bucket.try(:created_at) || Time.now
    end

    # Maybe should be last modified file?  But there is no index, not great query.
    def last_modified
      last_updated_bucket.try(:updated_at) || Time.now
    end

    def children
      return [] if bucket.nil?

      folder_names = Metis::Folder.where(bucket: bucket, folder: nil).select(:folder_name).map(&:folder_name)
      file_names = Metis::File.where(bucket: bucket, folder: nil).select(:file_name).map(&:file_name)

      folder_names.map { |name| FolderResourceNode.new(user, self, name, bucket) } + \
        file_names.map { |name| FileResourceNode.new(user, self, name, bucket) }
    end

    def bucket
      @bucket ||= Metis::Bucket.where(name: path_segment, project_name: parent.path_segment).first
    end

    def path
      "/"
    end
  end

  class FolderResourceNode < DataResourceNode
    attr_reader :bucket, :path

    def initialize(user, parent, segment, bucket)
      super(user, parent, segment)
      @bucket = bucket
      @path = parent.path + segment + "/"
    end

    def creation_date
      folder.try(:created_at) || Time.now
    end

    def last_modified
      folder.try(:updated_at) || Time.now
    end

    def children
      return [] if folder.nil?

      folder.folders.map { |f| FolderResourceNode.new(user, self, f.folder_name, bucket) } + \
        folder.files.map { |f| FileResourceNode.new(user, self, f.file_name, bucket) }
    end

    def folder
      @folder ||= Metis::Folder.from_path(bucket, path)
    end
  end

  class FileResourceNode < DataResourceNode
    attr_reader :bucket, :path

    def initialize(user, parent, segment, bucket)
      super(user, parent, segment)
      @bucket = bucket
      @path = parent.path + segment
    end

    def file
      @file ||= Metis::File.from_path(bucket, path)
    end

    def creation_date
      return Time.now if file.nil?
      file.data_block.created_at
    end

    def last_modified
      return Time.now if file.nil?
      file.data_block.updated_at
    end

    def etag
      return "" if file.nil?
      "#{file.id}-#{file.data_block.md5_hash}"
    end

    def content_length
      return 0 if file.nil?
      stat.size
    end

    def stat
      return nil if file.nil?
      @stat ||= ::File.stat(file.data_block.location)
    end

    def directory?
      false
    end
  end
end
