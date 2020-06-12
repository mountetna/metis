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

    def make_collection
      raise NotFound if inhabitant.nil?
      raise Forbidden unless is_writable?(:directory)
      raise Conflict unless inhabitant.mkdir!

      Created
    end

    def get(request, response)
      raise NotFound unless exist?

      unless directory?
        # Files are actually sent via apache, which swaps the body out of a response based on this header.
        response['X-Sendfile'] = inhabitant.file.data_block.location
      end

      OK
    end

    def put(request, response)
      raise NotFound if inhabitant.nil?
      raise Forbidden unless is_writable?(:file)

      io = request.body
      tempfile = Tempfile.new
      open(tempfile, "wb") do |file|
        while part = io.read(8192)
          file << part
        end
      end

      raise Forbidden unless inhabitant.upload!(tempfile)

      OK
    end

    def delete
      raise NotFound unless exist?
      raise Forbidden unless inhabitant.delete!

      NoContent
    end

    def copy(dest_path, overwrite = false, depth = nil)
      do_copy(dest_path, overwrite, depth, false)
    end

    def move(dest_path, overwrite=false)
      do_copy(dest_path, overwrite, nil, true)
    end

    def children
      return [] unless exist?

      inhabitant.children.map do |node|
        child node.path_segment
      end
    end

    def is_writable?(type)
      !inhabitant.nil? && inhabitant.is_writable?(type)
    end

    def exist?
      !inhabitant.nil? && inhabitant.exist?
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

    # For now, depth is ignored.
    def do_copy(dest_path, overwrite, depth, is_move)
      raise NotFound unless exist?
      raise Forbidden unless inhabitant.copyable?

      dest = DataResourceNode.descend(dest_path, user)
      raise PreconditionFailed if dest.exist? && !overwrite

      Metis.instance.db.transaction do
        if dest.exist?
          raise Conflict unless dest.delete!
        end

        raise NotFound unless inhabitant.copy!(dest)
        inhabitant.delete! if is_move
      end

      NoContent
    end

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

    def parent_folder
      parent.respond_to?(:folder) ? parent.folder : nil
    end

    def find_child(segment)
      children.find do |node|
        node.path_segment == segment
      end || writable_edge_node(segment)
    end

    def writable_edge_node(segment)
      nil
    end

    def copyable?
      false
    end

    def copy!(dest)
      false
    end

    def delete!
      false
    end

    def is_writable?(type)
      false
    end

    def mkdir!
      false
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

    def exist?
      true
    end

    def bucket
      nil
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
      bucket&.created_at || Time.now
    end

    # Maybe should be last modified file?  But there is no index, not great query.
    def last_modified
      bucket&.updated_at || Time.now
    end

    def children
      return [] if bucket.nil?

      folder_names = Metis::Folder.where(bucket: bucket, folder_id: nil).select(:folder_name).map(&:folder_name)
      file_names = Metis::File.where(bucket: bucket, folder_id: nil).select(:file_name).map(&:file_name)

      folder_names.map { |name| FolderResourceNode.new(user, self, name, bucket) } + \
        file_names.map { |name| FileResourceNode.new(user, self, name, bucket) }
    end

    def writable_edge_node(segment)
      WritableEdgeNode.new(user, self, segment, bucket)
    end

    def bucket
      @bucket ||= Metis::Bucket.where(name: path_segment, project_name: parent.path_segment).first
    end

    def path
      ""
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
      folder&.created_at || Time.now
    end

    def last_modified
      folder&.updated_at || Time.now
    end

    def copyable?
      true
    end

    def copy!(dest)
      return false unless dest.bucket
      Metis::Folder.find_or_create(folder_id: dest.parent_folder&.id, folder_name: dest.path_segment, bucket_id: dest.bucket.id, project_name: dest.bucket.project_name) do |f|
        f.author = folder.author
      end
      true
    end

    def delete!
      Metis.instance.db.transaction do
        Metis::File.where(folder: folder).delete
        Metis::Folder.where(folder: folder).delete
        folder.remove!
      end
    end

    def children
      return [] if folder.nil?

      folder.folders.map { |f| FolderResourceNode.new(user, self, f.folder_name, bucket) } + \
        folder.files.map { |f| FileResourceNode.new(user, self, f.file_name, bucket) }
    end

    def folder
      @folder ||= Metis::Folder.from_path(bucket, path).last
    end

    def writable_edge_node(segment)
      WritableEdgeNode.new(user, self, segment, bucket)
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

    def copyable?
      true
    end

    def copy!(dest)
      return false unless dest.bucket
      Metis::File.find_or_create(folder_id: dest.parent_folder&.id, file_name: dest.path_segment, bucket_id: dest.bucket.id, project_name: dest.bucket.project_name) do |f|
        f.author = file.author
        f.data_block = file.data_block
      end
      true
    end

    def delete!
      file.remove!
      true
    end

    def stat
      return nil if file.nil?
      @stat ||= ::File.stat(file.data_block.location)
    end

    def directory?
      false
    end

    def is_writable?(type)
      type == :file
    end

    def upload!(uploaded_file)
      # Most of this is copied from a combination of upload_controller and etna_controller.
      # Ideally this would be captured in a service class and shareable.
      blob = Metis::Blob.new(tempfile: uploaded_file)

      upload = Metis::Upload.find_or_create(
          file_name: path,
          bucket: bucket,
          metis_uid: metis_uid,
          project_name: bucket.project_name
      ) do |f|
        f.author = Metis::File.author(user)
        f.file_size = 0
        f.current_byte_position = 0
        f.next_blob_size = ::File.size(blob.path)
        f.next_blob_hash = Metis::File.md5(blob.path)
      end

      upload.append_blob(blob, 0, '')

      folder_path, file_name = Metis::File.path_parts(upload.file_name)
      folder = Metis::Folder.from_path(bucket, folder_path).last

      file = Metis::File.from_folder(bucket, folder, file_name)

      if file && file.read_only?
        return false
      end

      if Metis::Folder.exists?(file_name, upload.bucket, folder)
        return false
      end

      upload.finish!
      true
    end

    def metis_uid
      Metis.instance.sign.uid
    end
  end

  class WritableEdgeNode < FileResourceNode
    def file
      nil
    end

    def exist?
      false
    end

    def is_writable?(type)
      true
    end

    def mkdir!
      Metis::Folder.create(
          folder: parent_folder,
          folder_name: path_segment,
          bucket: bucket,
          project_name: bucket.project_name,
          read_only: false,
          author:  Metis::File.author(user),
      )

      true
    end
  end
end
