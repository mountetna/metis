describe FolderController do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  before(:each) do
    default_bucket('athena')

    @metis_uid = Metis.instance.sign.uid

    set_cookie "#{Metis.instance.config(:metis_uid_name)}=#{@metis_uid}"
  end

  after(:each) do
    clear_stubs
  end

  context '#list' do
    before(:each) do
      @wisdom_file = create_file('athena', 'wisdom.txt', WISDOM)
      stub_file('wisdom.txt', WISDOM, :athena)

      @blueprints_folder = create_folder('athena', 'blueprints')

      @helmet_folder = create_folder('athena', 'helmet', folder: @blueprints_folder)

      @helmet_file = create_file('athena', 'helmet.jpg', HELMET, folder: @helmet_folder)
      stub_file('blueprints/helmet/helmet.jpg', HELMET, :athena)
    end

    it 'should return a list of files and folders for the current folder' do
      # our files
      token_header(:editor)
      get('/athena/list/files/')

      expect(last_response.status).to eq(200)

      expect(json_body[:files].first).to include(
        file_name: 'wisdom.txt',
        author: 'metis|Metis',
        project_name: 'athena',
        bucket_name: 'files',
        size: 66,
        file_hash: Digest::MD5.hexdigest(WISDOM),
        download_url: a_string_matching(%r{http.*athena/download})
      )
      expect(json_body[:folders].first).to include(
        folder_name: 'blueprints',
        author: 'metis|Metis',
        project_name: 'athena',
        bucket_name: 'files'
      )
    end

    it 'should list files from a sub-folder' do
      # our files
      token_header(:editor)
      get('/athena/list/files/blueprints/helmet')

      expect(last_response.status).to eq(200)

      expect(json_body[:files].first).to include(
        file_name: 'helmet.jpg',
        author: 'metis|Metis',
        project_name: 'athena',
        size: HELMET.length,
        file_hash: Digest::MD5.hexdigest(HELMET),
        download_url: a_string_matching(%r{http.*athena/download.*blueprints/helmet/helmet.jpg})
      )
    end

    it 'should require a complete path' do
      # our files
      token_header(:editor)
      get('/athena/list/files/helmet')

      expect(last_response.status).to eq(422)

      expect(json_body[:error]).to eq('Invalid folder')
    end
  end

  context '#create' do
    def post_create_folder path, params={}
      json_post("athena/create_folder/files/#{path}", params)
    end

    it 'creates a folder with the given name' do
      token_header(:editor)
      post_create_folder('Helmet Blueprints')

      expect(last_response.status).to eq(200)

      folder = Metis::Folder.first
      expect(folder).not_to be_nil
      expect(folder.folder_name).to eq('Helmet Blueprints')
      expect(File.directory?(folder.location)).to be_truthy

      # Clean up
      Dir.delete(folder.location)
    end

    it 'refuses to create folders with invalid names' do
      token_header(:editor)
      post_create_folder("Helmet\nBlueprints")

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid path')
    end

    it 'creates nested folders' do
      blueprints_folder = create_folder('athena', 'blueprints')
      stub_folder('blueprints', 'athena')
      token_header(:editor)
      post_create_folder('blueprints/Helmet Blueprints')

      expect(last_response.status).to eq(200)

      folder = Metis::Folder.last
      expect(folder).not_to be_nil
      expect(folder.folder_path).to eq(['blueprints', 'Helmet Blueprints'])

      # clean up
      Dir.delete(folder.location)
    end

    it 'refuses to set a file as parent' do
      wisdom_file = create_file('athena', 'wisdom.txt', WISDOM)

      token_header(:editor)
      post_create_folder('wisdom.txt/Helmet Blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')
    end

    it 'refuses to create existing folder' do
      token_header(:editor)
      blueprints_folder = create_folder('athena', 'blueprints')
      post_create_folder('blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Folder exists')
    end

    it 'refuses to create folders with non-existent parent folder' do
      token_header(:editor)
      post_create_folder('blueprints/Helmet Blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')
    end

    it 'sets a parent folder' do
      blueprints_folder = create_folder('athena', 'blueprints')
      stub_folder('blueprints', 'athena')
      token_header(:editor)
      post_create_folder('blueprints/Helmet Blueprints')

      folder = Metis::Folder.last

      expect(last_response.status).to eq(200)
      expect(Metis::Folder.count).to eq(2)
      expect(folder.folder_path).to eq([ 'blueprints', 'Helmet Blueprints'])
      expect(folder.folder).to eq(blueprints_folder)

      # clean up
      Dir.delete(folder.location)
    end
  end

  context '#remove' do
    before(:each) do
      @blueprints_folder = create_folder('athena', 'blueprints')
      stub_folder('blueprints', 'athena')
      expect(@blueprints_folder.has_directory?).to be_truthy
    end

    def remove_folder path
      delete("athena/remove_folder/files/#{path}")
    end

    it 'removes a folder' do
      token_header(:editor)
      location = @blueprints_folder.location
      remove_folder('blueprints')

      expect(last_response.status).to eq(200)
      expect(::Dir.exists?(location)).to be_falsy
      expect(Metis::Folder.count).to eq(0)
    end

    it 'refuses to remove a folder without permissions' do
      token_header(:viewer)
      remove_folder('blueprints')

      expect(last_response.status).to eq(403)
      expect(Metis::Folder.count).to eq(1)
    end

    it 'refuses to remove a non-existent folder' do
      # we attempt to remove a folder that does not exist
      token_header(:editor)
      remove_folder('glueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')

      # the actual folder is untouched
      expect(Metis::Folder.last).to eq(@blueprints_folder)
      expect(@blueprints_folder).to be_has_directory
    end

    it 'refuses to remove a folder that contains file data' do
      stub_file('blueprints/helmet.jpg', HELMET, :athena)

      token_header(:editor)
      remove_folder('blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Cannot remove folder')
      expect(Metis::Folder.last).to eq(@blueprints_folder)
      expect(@blueprints_folder).to be_has_directory
      expect(Dir.entries(@blueprints_folder.location).size).to eq(3)
    end

    it 'refuses to remove a read-only folder' do
      @blueprints_folder.read_only = true
      @blueprints_folder.save
      @blueprints_folder.refresh

      token_header(:editor)
      remove_folder('blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Cannot remove folder')
      expect(Metis::Folder.last).to eq(@blueprints_folder)
    end

    it 'refuses to remove a read-only folder even for an admin' do
      @blueprints_folder.read_only = true
      @blueprints_folder.save
      @blueprints_folder.refresh

      token_header(:editor)
      remove_folder('blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Cannot remove folder')
      expect(Metis::Folder.last).to eq(@blueprints_folder)
      expect(@blueprints_folder).to be_has_directory
    end
  end

  context '#protect' do
    before(:each) do
      @blueprints_folder = create_folder('athena', 'blueprints')
      stub_folder('blueprints', 'athena')
      expect(@blueprints_folder).not_to be_read_only
    end

    def protect_folder path
      json_post("athena/protect_folder/files/#{path}",{})
    end

    it 'protects a folder' do
      token_header(:admin)
      protect_folder('blueprints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(200)
      expect(@blueprints_folder).to be_read_only
    end

    it 'refuses to protect a folder without permissions' do
      token_header(:editor)
      protect_folder('blueprints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(403)
      expect(@blueprints_folder).not_to be_read_only
    end

    it 'refuses to protect a non-existent folder' do
      # we attempt to protect a folder that does not exist
      token_header(:admin)
      protect_folder('glueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')

      # the actual folder is untouched
      @blueprints_folder.refresh
      expect(@blueprints_folder).not_to be_read_only
    end

    it 'refuses to protect a read-only folder' do
      @blueprints_folder.read_only = true
      @blueprints_folder.save
      @blueprints_folder.refresh

      token_header(:admin)
      protect_folder('blueprints')

      expect(last_response.status).to eq(403)
      expect(json_body[:error]).to eq('Folder is read-only')
      @blueprints_folder.refresh
      expect(@blueprints_folder).to be_read_only
    end
  end

  context '#unprotect' do
    before(:each) do
      @blueprints_folder = create_folder('athena', 'blueprints', read_only: true)
      stub_folder('blueprints', 'athena')
      expect(@blueprints_folder).to be_read_only
    end

    def unprotect_folder path
      json_post("athena/unprotect_folder/files/#{path}",{})
    end

    it 'unprotects a folder' do
      token_header(:admin)
      unprotect_folder('blueprints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(200)
      expect(@blueprints_folder).not_to be_read_only
    end

    it 'refuses to unprotect a folder without permissions' do
      token_header(:editor)
      unprotect_folder('blueprints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(403)
      expect(@blueprints_folder).to be_read_only
    end

    it 'refuses to unprotect a non-existent folder' do
      # we attempt to unprotect a folder that does not exist
      token_header(:admin)
      unprotect_folder('glueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')

      # the actual folder is untouched
      @blueprints_folder.refresh
      expect(@blueprints_folder).to be_read_only
    end

    it 'refuses to unprotect a writeable folder' do
      @blueprints_folder.read_only = false
      @blueprints_folder.save

      token_header(:admin)
      unprotect_folder('blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Folder is not protected')
      @blueprints_folder.refresh
      expect(@blueprints_folder).not_to be_read_only
    end
  end

  context '#rename' do
    before(:each) do
      @blueprints_folder = create_folder('athena', 'blueprints')
      stub_folder('blueprints', 'athena')
    end

    after(:each) do
      Dir.delete(@blueprints_folder.location) if ::File.exists?(@blueprints_folder.location)
    end

    def rename_folder path, new_path
      json_post("athena/rename_folder/files/#{path}", new_folder_path: new_path)
    end

    it 'renames a folder' do
      token_header(:editor)
      rename_folder('blueprints', 'blue-prints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(200)
      expect(@blueprints_folder.folder_name).to eq('blue-prints')
      expect(@blueprints_folder).to be_has_directory
    end

    it 'refuses to rename a folder to an invalid name' do
      token_header(:editor)
      rename_folder('blueprints', "blue\nprints")

      @blueprints_folder.refresh
      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid path')
      expect(@blueprints_folder.folder_name).to eq('blueprints')
    end

    it 'refuses to rename a folder without permissions' do
      token_header(:viewer)
      rename_folder('blueprints','blue-prints')

      @blueprints_folder.refresh
      expect(last_response.status).to eq(403)
      expect(@blueprints_folder.folder_name).to eq('blueprints')
    end

    it 'refuses to rename a non-existent folder' do
      # we attempt to rename a folder that does not exist
      token_header(:editor)
      rename_folder('redprints','blue-prints')

      expect(last_response.status).to eq(404)
      expect(json_body[:error]).to eq('Folder not found')

      # the actual folder is untouched
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_name).to eq('blueprints')
    end

    it 'refuses to rename over an existing folder' do
      helmet_folder = create_folder('athena', 'helmet')
      stub_folder('helmet', 'athena')

      token_header(:editor)
      rename_folder('blueprints','helmet')

      expect(last_response.status).to eq(403)
      expect(json_body[:error]).to eq('Cannot overwrite existing folder')

      # the actual folder is untouched
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_name).to eq('blueprints')
      expect(@blueprints_folder).to be_has_directory
    end

    it 'refuses to rename a read-only folder' do
      @blueprints_folder.read_only = true
      @blueprints_folder.save

      token_header(:editor)
      rename_folder('blueprints', 'blue-prints')

      expect(last_response.status).to eq(403)
      expect(json_body[:error]).to eq('Folder is read-only')
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_path).to eq(['blueprints'])
    end

    it 'can move a folder to a new folder' do
      contents_folder = create_folder('athena', 'contents')
      stub_folder('contents', 'athena')

      token_header(:editor)
      rename_folder('blueprints', 'contents/blueprints')

      expect(last_response.status).to eq(200)
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_path).to eq(['contents','blueprints'])
      expect(@blueprints_folder.folder).to eq(contents_folder)
    end

    it 'will not move a folder to a read-only folder' do
      contents_folder = create_folder('athena', 'contents', read_only: true)
      stub_folder('contents', 'athena')

      token_header(:editor)
      rename_folder('blueprints', 'contents/blueprints')

      expect(last_response.status).to eq(403)
      expect(json_body[:error]).to eq('Folder is read-only')
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_path).to eq(['blueprints'])
      expect(@blueprints_folder.folder).to be_nil
    end

    it 'will not move a folder to a non-existent folder' do
      token_header(:editor)
      rename_folder('blueprints', 'contents/blueprints')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid folder')
      @blueprints_folder.refresh
      expect(@blueprints_folder.folder_path).to eq(['blueprints'])
      expect(@blueprints_folder.folder).to be_nil
    end
  end
end