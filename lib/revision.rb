require 'pry'
class Metis
  class Revision
    FILENAME_MATCH=/[^<>:;,?"*\|\/\x00-\x1f]+/x

    FILEPATH_MATCH=%r!
      ^metis://
      (?<project_name>[^/]*?)
      /
      (?<bucket_name>[^/]*?)
      /
      (?<folder_path>.*)
      $
    !x

    attr_reader :source, :dest
    def initialize(params)
      raise Etna::BadRequest, 'All revisions require "source" parameter' unless params.has_key? :source
      raise Etna::BadRequest, 'All revisions require "dest" parameter' unless params.has_key? :dest

      raise Etna::BadRequest, 'Invalid source path' unless valid_file_path?(params[:source])

      @source = params[:source]
      @dest = params[:dest]
      # TODO: Will have to handle DELETE differently,
      #       when params[:dest] will be nil
    end

    def self.path_from_parts(project, bucket, file_name, folder_path=nil)
      return "metis://#{project}/#{bucket}/#{file_name}" unless folder_path

      return "metis://#{project}/#{bucket}/#{folder_path}/#{file_name}"
    end

    def self.extract_bucket_from_path(path)
      # Assumes Metis file paths are in the form
      #    metis://<project>/<bucket>/<folder path>/<file name>
      # Splitting the above produces
      #   ["metis", "", "<project>", "<bucket>", "<folder path>" ... "file name"]
      # Should this be in a central gem, like etna, so
      #   we can share it across applications?
      return FILEPATH_MATCH.match(path)[:bucket_name]
    end

    def self.extract_file_path_from_path(path)
      # Assumes Metis file paths are in the form
      #    metis://<project>/<bucket>/<folder path>/<file name>
      # Splitting the above produces
      #   ["metis", "", "<project>", "<bucket>", "<folder path>" ... "file name"]
      # Should this be in a central gem, like etna, so
      #   we can share it across applications?
      return FILEPATH_MATCH.match(path)[:folder_path]
    end

    def validate_access_to_buckets(user_authorized_bucket_names)
      raise Etna::Forbidden, "Cannot access the source bucket #{source_bucket}" unless user_authorized_bucket_names.include? source_bucket
      raise Etna::Forbidden, "Cannot access the destination bucket #{dest_bucket}" unless user_authorized_bucket_names.include? dest_bucket
    end

    def source_bucket
      Metis::Revision.extract_bucket_from_path(@source)
    end

    def dest_bucket
      Metis::Revision.extract_bucket_from_path(@dest)
    end

    def source_file_path
      Metis::Revision.extract_file_path_from_path(@source)
    end

    def dest_file_path
      Metis::Revision.extract_file_path_from_path(@dest)
    end

    private

    def valid_file_path?(path)
      FILEPATH_MATCH.match(path)
    end
  end
end
