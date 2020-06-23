describe Metis::WebDavResource do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  after(:each) do
    stubs.clear
  end

  # Request configurations
  let(:params) { {} }
  let(:env) { {} }

  # User / role configurations
  let(:project_role) { :admin }
  let(:other_project_role) { :viewer }
  let(:permissions) { [[project_name, project_role], [other_project_name, other_project_role]] }

  let(:encoded_permissions) do
    permissions.inject({}) do |projects_by_role, (proj_name, role)|
      (projects_by_role[role] ||= []).push(proj_name)
      projects_by_role
    end.map { |role, projs| "#{role.to_s[0, 1]}:#{projs.join(',')}" }.join(';')
  end

  let(:user) { {email: 'zeus@olympus.org', first: 'Zeus', perm: encoded_permissions} }

  # File configurations
  let(:project_name) { 'labors' }
  let(:other_project_name) { 'sports' }
  let(:bucket_name) { 'files' }
  let(:other_bucket_name) { 'files' }
  let(:bucket_access) { 'viewer' }
  let(:other_bucket_access) { 'viewer' }
  let!(:bucket) { default_bucket(project_name, bucket_name: bucket_name, access: bucket_access) }
  let!(:other_bucket) { default_bucket(other_project_name, bucket_name: other_bucket_name, access: other_bucket_access) }
  let(:directories) { [] }
  let(:file_name) { 'abc.txt' }
  let(:folder) { directories_to_folder(directories, project_name, bucket) }
  let(:contents) { 'abcdefg' }
  let!(:location) { stubs.create_file(project_name, bucket_name, file_name, contents) }
  let(:read_only) { false }
  let!(:file) { create_file(project_name, file_name, contents, bucket: bucket, folder: folder, read_only: read_only) }

  let(:other_directories) { [] }
  let(:other_file_name) { 'def.txt' }
  let(:other_folder) { directories_to_folder(other_directories, other_project_name, other_bucket) }
  let(:other_contents) { 'hijklmno' }
  let!(:other_location) { stubs.create_file(other_project_name, other_bucket_name, other_file_name, other_contents) }
  let!(:other_file) { create_file(project_name, other_file_name, other_contents, bucket: other_bucket, folder: other_folder) }

  # Utility values
  let(:propfind_xml) do
    <<-PROPFIND
<?xml version="1.0" encoding="utf-8" ?>
 <D:propfind xmlns:D="DAV:">
   <D:allprop/>
 </D:propfind>
    PROPFIND
  end

  def application
    @application ||= Etna::Application.instance
  end

  let(:subject_request) do
    # token = application.sign.jwt_token(user)
    token = Base64.strict_encode64(user.to_json)
    auth = Base64.strict_encode64("user:#{token}")
    header('Authorization', "Basic #{auth}")

    custom_request(method, path, params, env)
    last_response
  end

  let(:statuses) do
    response_xml.xpath('//d:multistatus/d:response').map do |response|
      propstat = response.xpath('//d:propstat').first
      propstat.xpath('//d:status').first.text
    end
  end

  let(:hrefs) do
    response = response_xml.xpath('//d:multistatus/d:response').last
    response.xpath('//d:href').map(&:text).map { |href| URI.parse(href).path }
  end

  def response_xml
    @response_xml ||= Nokogiri.XML(last_response.body) { |config| config.strict }
  end

  def directories_to_folder(directories, project_name, bucket)
    directories.inject(nil) do |parent, segment|
      create(:folder, folder: parent, folder_name: segment, project_name: project_name, bucket: bucket, author: 'someguy@example.org')
    end
  end

  ['copy', 'move'].each do |verb|
    describe verb do
      let(:method) { verb.upcase }
      let(:source_path) { file_name }
      let(:destination_path) { "new_thing" }
      let(:destination_bucket_name) { destination_bucket.name }
      let(:destination_project_name) { project_name }
      let(:destination_bucket) { bucket }
      let(:overwrite) { true }
      let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{source_path}" }
      let(:env) do
        {
            'HTTP_OVERWRITE' => overwrite ? 'T' : 'F',
            'HTTP_DESTINATION' => "#{METIS_URL}/webdav/projects/#{destination_project_name}/#{destination_bucket_name}/#{destination_path}",
        }
      end

      subject do
        subject_request
        expect(last_response.status).to eq(204)

        {
            sf_remains: !Metis::File.from_path(bucket, source_path).nil?,
            sd_remains: !Metis::Folder.from_path(bucket, source_path).last.nil?,
            dd_exists: !Metis::Folder.from_path(destination_bucket, destination_path).last.nil?,
            df_exists: !Metis::File.from_path(destination_bucket, destination_path).nil?,
        }
      end

      it { is_expected.to eq({dd_exists: false, df_exists: true, sd_remains: false, sf_remains: verb == 'copy', }) }

      describe 'from a folder' do
        let(:directories) { ['adirectory'] }
        let(:source_path) { directories.first }

        it { is_expected.to eq({dd_exists: true, df_exists: false, sf_remains: false, sd_remains: verb == 'copy', }) }
      end

      describe 'for non existent source' do
        let(:source_path) { "abc" }

        it 'is not allowed' do
          subject_request
          expect(last_response.status).to eq(404)
        end
      end

      describe 'for a project dir' do
        let(:path) { "/webdav/projects/#{project_name}/" }

        it 'is not allowed' do
          subject_request
          expect(last_response.status).to eq(403)
        end
      end
    end
  end


  describe 'mkcol' do
    let(:method) { 'MKCOL' }
    let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{mkcol_dir}" }
    let(:mkcol_dir) { 'my_new_dir' }

    subject do
      subject_request
      expect(last_response.status).to eq(201)
      Metis::Folder.from_path(bucket, mkcol_dir + "/").last&.folder_path
    end

    it { is_expected.to eq [mkcol_dir] }

    context 'for a folder in the root path' do
      let(:path) { "/webdav/#{mkcol_dir}/" }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(403)
      end
    end

    context 'for a folder in a project path' do
      let(:path) { "/webdav/#{project_name}/#{mkcol_dir}/" }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(403)
      end
    end

    context 'for an existing directory' do
      let(:directories) { ["abc"] }
      let(:mkcol_dir) { directories.first }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(405)
      end

      context 'as the child of it' do
        let(:mkcol_dir) { "#{directories.first}/def" }

        it { is_expected.to eq [directories.first, "def"] }
      end
    end

    context 'for an existing file' do
      let(:file_name) { mkcol_dir }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(405)
      end
    end
  end

  describe 'put' do
    let(:method) { 'PUT' }
    let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{put_file_name}" }
    let(:put_file_name) { 'my_new_file' }
    let(:put_file_contents) { 'somebody once told me the world is kinda baloney' }
    let(:env) { {input: put_file_contents} }

    subject do
      subject_request
      expect(last_response.status).to eq(200)
      ::File.read(Metis::File.from_path(bucket, "#{put_file_name}").data_block.location)
    end

    it { is_expected.to eq(put_file_contents) }

    context 'for a file in the root path' do
      let(:path) { "/webdav/#{put_file_name}" }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(401)
      end
    end

    context 'for a file in a project path' do
      let(:path) { "/webdav/#{project_name}/#{put_file_name}" }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(401)
      end
    end

    context 'for a directory' do
      let(:directories) { [put_file_name] }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(403)
      end
    end

    context 'for a read only file' do
      let(:file_name) { put_file_name }
      let(:read_only) { true }

      it 'is not allowed' do
        subject_request
        expect(last_response.status).to eq(403)
      end
    end

    context 'for an existing file' do
      let(:file_name) { put_file_name }

      it { is_expected.to eq(put_file_contents) }
    end
  end

  describe 'get' do
    let(:method) { 'GET' }


    subject do
      subject_request
      expect(last_response.status).to eq(200)
      last_response.headers['X-Sendfile']
    end

    describe 'for top level' do
      let(:path) { '/webdav/projects/' }

      it { is_expected.to be_nil }
    end

    describe 'for a project' do
      let(:path) { "/webdav/projects/#{project_name}/" }

      it { is_expected.to be_nil }
    end

    describe 'for a bucket' do
      let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/" }

      it { is_expected.to be_nil }
    end

    describe 'for a file' do
      let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{file_name}" }

      it { is_expected.to eq(location) }
    end
  end

  describe 'propfind' do
    let(:method) { 'PROPFIND' }
    let(:env) { {'HTTP_DEPTH' => '1', input: propfind_xml} }

    subject do
      subject_request
      expect(last_response.status).to eq(207)
      statuses.each { |s| expect(s).to match(/200 OK/) }
      # Consistent ordering so that tests are less fragile.
      hrefs.sort
    end

    describe 'listing projects' do
      let(:path) { '/webdav/projects/' }

      it { is_expected.to eq(%W[/webdav/projects/ /webdav/projects/#{project_name}/ /webdav/projects/#{other_project_name}/].sort) }

      context 'when missing access to a project' do
        let(:permissions) { [[project_name, project_role]] }

        it { is_expected.to eq(%W[/webdav/projects/ /webdav/projects/#{project_name}/].sort) }

        context 'but the user is a super admin' do
          let(:permissions) { [[:administration, :admin]] }

          it { is_expected.to eq(%W[/webdav/projects/ /webdav/projects/#{project_name}/ /webdav/projects/#{other_project_name}/].sort) }
        end
      end
    end

    describe 'listing buckets' do
      let(:path) { "/webdav/projects/#{other_project_name}/" }

      it { is_expected.to eq(%W[/webdav/projects/#{other_project_name}/ /webdav/projects/#{other_project_name}/#{other_bucket_name}/].sort) }

      context 'when role is less than bucket access level' do
        let(:other_bucket_access) { 'editor' }

        it { is_expected.to eq(%W[/webdav/projects/#{other_project_name}/].sort) }
      end

      context 'when the parent project is inaccessible' do
        let(:permissions) { [] }

        it 'should fail to find the resource' do
          subject_request
          expect(last_response.status).to eq(404)
        end
      end
    end

    describe 'listing folders and files' do
      let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/" }

      it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/ /webdav/projects/#{project_name}/#{bucket_name}/#{file_name}].sort) }

      context 'when multiple items exist together' do
        let(:other_project_name) { project_name }
        let(:other_bucket_name) { bucket_name }
        let(:other_bucket) { bucket }

        it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/ /webdav/projects/#{project_name}/#{bucket_name}/#{file_name} /webdav/projects/#{project_name}/#{bucket_name}/#{other_file_name}].sort) }

        context 'when some items are folders' do
          let(:other_directories) { ['folder_1'] }

          it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/ /webdav/projects/#{project_name}/#{bucket_name}/#{file_name} /webdav/projects/#{project_name}/#{bucket_name}/folder_1/].sort) }
        end
      end

      describe 'listing directories' do
        let(:directories) { ['a', 'b'] }

        it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/ /webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/].sort) }

        context 'inside of other directories' do
          let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/" }

          it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/ /webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/#{directories[1]}/].sort) }

          context 'containing files' do
            let(:path) { "/webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/#{directories[1]}/" }

            it { is_expected.to eq(%W[/webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/#{directories[1]}/ /webdav/projects/#{project_name}/#{bucket_name}/#{directories.first}/#{directories[1]}/#{file_name}].sort) }

            context 'without permissions' do
              let(:permissions) { [] }

              it 'should fail to find the resource' do
                subject_request
                expect(last_response.status).to eq(404)
              end
            end
          end
        end
      end
    end
  end
end
