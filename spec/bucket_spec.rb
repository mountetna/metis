# Bucket permissions are tested using folder#list, but should apply to any
# endpoint calling require_bucket (that is, most of them)

describe Metis::Bucket do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  before(:each) do
    @metis_uid = Metis.instance.sign.uid

    set_cookie "#{Metis.instance.config(:metis_uid_name)}=#{@metis_uid}"
  end

  after(:each) do
    stubs.clear

    expect(stubs.contents(:athena)).to be_empty
  end

  it 'forbids users from accessing buckets by project role' do

    bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

    # the admin is always allowed
    token_header(:admin)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(200)

    # the editor is allowed here
    token_header(:editor)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(200)

    # the viewer is forbidden
    token_header(:viewer)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(403)
  end

  it 'forbids users from accessing buckets by email id' do
    bucket = create(:bucket, project_name: 'athena', name: 'my_bucket', access: 'athena@olympus.org', owner: 'metis')

    # the admin is always allowed
    token_header(:admin)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(200)

    # the editor (metis@olympus.org) is forbidden here
    token_header(:editor)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(403)

    # the viewer (athena@olympus.org) is allowed
    token_header(:viewer)
    get('/athena/list/my_bucket/')
    expect(last_response.status).to eq(200)
  end
end

describe BucketController do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  before(:each) do
    @metis_uid = Metis.instance.sign.uid

    set_cookie "#{Metis.instance.config(:metis_uid_name)}=#{@metis_uid}"
  end

  after(:each) do
    stubs.clear

    expect(stubs.contents(:athena)).to be_empty
  end

  context '#list' do
    it 'returns a list of buckets for the current project' do
      bucket1 = create( :bucket, project_name: 'athena', name: 'files', access: 'viewer', owner: 'metis' )
      bucket2 = create( :bucket, project_name: 'athena', name: 'extra', access: 'viewer', owner: 'metis' )
      bucket3 = create( :bucket, project_name: 'athena', name: 'magma', access: 'viewer', owner: 'athena' )

      token_header(:viewer)
      get('/athena/list')

      expect(last_response.status).to eq(200)

      expect(json_body[:buckets].count).to eq(2)
      expect(json_body[:buckets].map{|b| b[:bucket_name]}).to include('extra', 'files')
    end

    it 'returns only visible buckets for the current project' do
      bucket1 = create( :bucket, project_name: 'athena', name: 'files', access: 'viewer', owner: 'metis' )
      bucket2 = create( :bucket, project_name: 'athena', name: 'extra', access: 'editor', owner: 'metis' )
      bucket3 = create( :bucket, project_name: 'athena', name: 'magma', access: 'administrator', owner: 'athena' )

      token_header(:viewer)
      get('/athena/list')

      expect(last_response.status).to eq(200)

      expect(json_body[:buckets]).to eq([bucket1.to_hash])
    end
  end

  context '#create' do
    it 'creates a new bucket' do
      token_header(:admin)
      json_post('/athena/bucket/create/my_bucket', owner: 'metis', access: 'viewer')

      # the record is created
      expect(Metis::Bucket.count).to eq(1)
      bucket = Metis::Bucket.first
      expect(bucket.name).to eq('my_bucket')
      expect(bucket.owner).to eq('metis')

      expect(last_response.status).to eq(200)
      expect(json_body[:bucket]).to eq(bucket.to_hash)
    end

    it 'requires admin permissions' do
      token_header(:editor)
      json_post('/athena/bucket/create/my_bucket', owner: 'metis', access: 'viewer')

      expect(Metis::Bucket.count).to eq(0)
      expect(last_response.status).to eq(403)
    end

    it 'prevents illegal bucket names' do
      token_header(:admin)
      json_post("/athena/bucket/create/My\nBucket", owner: 'metis', access: 'viewer')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Illegal bucket name')
    end

    it 'requires a valid owner' do
      token_header(:admin)
      json_post("/athena/bucket/create/my_bucket", owner: 'thetis', access: 'viewer')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid owner')
    end

    it 'requires a valid access' do
      token_header(:admin)
      json_post("/athena/bucket/create/my_bucket", owner: 'metis', access: 'casual')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid access')
    end

    it 'requires a valid access list' do
      token_header(:admin)
      json_post("/athena/bucket/create/my_bucket", owner: 'metis', access: 'metis,athena')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid access')
    end
  end

  context '#update' do
    before(:each) do
      Metis.instance.config(:hmac_keys).update(athena: Metis.instance.sign.uid)
    end

    after(:each) do
      Metis.instance.config(:hmac_keys).delete(:athena)
    end

    it 'requires an existing bucket' do
      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', owner: 'metis', access: 'viewer')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid bucket: "my_bucket"')
    end

    it 'requires admin permissions' do
      token_header(:editor)
      json_post('/athena/bucket/update/my_bucket', owner: 'metis', access: 'viewer')

      expect(Metis::Bucket.count).to eq(0)
      expect(last_response.status).to eq(403)
    end

    it 'updates a bucket' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', access: 'viewer', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      # the data is updated
      expect(bucket.name).to eq('my_bucket')
      expect(bucket.access).to eq('viewer')
      expect(bucket.description).to eq('My Bucket')

      # we get the new bucket back
      expect(last_response.status).to eq(200)
      expect(json_body[:bucket]).to eq(bucket.to_hash)
    end

    it 'cannot update owner' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', owner: 'athena', access: 'viewer', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      # the data is updated
      expect(bucket.name).to eq('my_bucket')
      expect(bucket.access).to eq('viewer')
      expect(bucket.description).to eq('My Bucket')

      # except the owner is unchanged
      expect(bucket.owner).to eq('metis')

      # we get the new bucket back
      expect(last_response.status).to eq(200)
      expect(json_body[:bucket]).to eq(bucket.to_hash)
    end

    it 'requires a legal access' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', owner: 'metis', access: 'casual', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      # the data remains
      expect(bucket.name).to eq('my_bucket')
      expect(bucket.owner).to eq('metis')
      expect(bucket.access).to eq('editor')
      expect(bucket.description).to be_nil

      # an error is returned
      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid access')
    end

    it 'renames a bucket' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', new_bucket_name: 'new_bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      # the record is updated
      expect(last_response.status).to eq(200)
      expect(bucket.name).to eq('new_bucket')
      expect(bucket.owner).to eq('metis')
      expect(bucket.access).to eq('editor')
      expect(bucket.description).to be_nil
    end
  end

  context '#remove' do
    it 'requires an existing bucket' do
      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid bucket: "my_bucket"')
    end

    it 'requires admin permissions' do
      token_header(:editor)
      delete('/athena/bucket/remove/my_bucket')

      expect(Metis::Bucket.count).to eq(0)
      expect(last_response.status).to eq(403)
    end

    it 'removes a bucket' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(200)
      expect(Metis::Bucket.count).to eq(0)
    end

    it 'removes a bucket with uploads' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')
      upload = create_upload( 'athena', 'wisdom.txt', @metis_uid, bucket: bucket)

      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(200)
      expect(Metis::Bucket.count).to eq(0)
    end

    it 'refuses to remove a non-empty bucket' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')
      stubs.create_bucket('athena', 'my_bucket')

      wisdom_file = create_file('athena', 'wisdom.txt', WISDOM, bucket: bucket)
      stubs.create_file('athena', 'my_bucket', 'wisdom.txt', WISDOM)

      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(422)
      expect(Metis::Bucket.count).to eq(1)
      expect(json_body[:error]).to eq('Cannot remove bucket')
    end
  end

  context '#find' do
    before(:each) do
      @bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'viewer', owner: 'metis')
      stubs.create_bucket('athena', 'my_bucket')

      @public_folder = create_folder('athena', 'public', bucket: @bucket)
      stubs.create_folder('athena', 'my_bucket', 'public')

      @wisdom_file = create_file('athena', 'wisdom.txt', WISDOM, bucket: @bucket, folder: @public_folder)
      stubs.create_file('athena', 'my_bucket', 'public', 'wisdom.txt', WISDOM)
    end

    after(:each) do
      stubs.clear

      expect(stubs.contents(:athena)).to be_empty
    end

    it 'returns files and folders according to supplied parameters' do
      token_header(:viewer)
      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: 'w%'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders]).to eq([])
      expect(json_body[:files].length).to eq(1)
      expect(json_body[:files].first[:file_name]).to eq(@wisdom_file.file_name)

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%i%'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders].length).to eq(1)
      expect(json_body[:folders].first[:folder_name]).to eq(@public_folder.folder_name)
      expect(json_body[:files].length).to eq(1)
      expect(json_body[:files].first[:file_name]).to eq(@wisdom_file.file_name)

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%ic%'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders].length).to eq(1)
      expect(json_body[:folders].first[:folder_name]).to eq(@public_folder.folder_name)
      expect(json_body[:files]).to eq([])
    end

    it 'can specify type flag to search only for files' do
      token_header(:viewer)
      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: 'w%',
        type: 'file'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders]).to eq([])
      expect(json_body[:files].length).to eq(1)
      expect(json_body[:files].first[:file_name]).to eq(@wisdom_file.file_name)

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%i%',
        type: 'file'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders]).to eq([])
      expect(json_body[:files].length).to eq(1)
      expect(json_body[:files].first[:file_name]).to eq(@wisdom_file.file_name)

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%ic%',
        type: 'file'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders].length).to eq([])
      expect(json_body[:files]).to eq([])
    end

    it 'can specify type flag to search only for folders' do
      token_header(:viewer)
      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: 'w%',
        type: 'folder'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders]).to eq([])
      expect(json_body[:files]).to eq([])

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%i%',
        type: 'folder'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders].length).to eq(1)
      expect(json_body[:folders].first[:folder_name]).to eq(@public_folder.folder_name)
      expect(json_body[:files]).to eq([])

      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: '%ic%',
        type: 'folder'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:folders].length).to eq(1)
      expect(json_body[:folders].first[:folder_name]).to eq(@public_folder.folder_name)
      expect(json_body[:files]).to eq([])
    end

    it 'returns error if user does not have access to view bucket' do
      restricted_bucket = create( :bucket, project_name: 'athena', name: 'restricted_bucket', access: 'editor', owner: 'metis')
      stubs.create_bucket('athena', 'restricted_bucket')

      public_folder = create_folder('athena', 'public', bucket: restricted_bucket)
      stubs.create_folder('athena', 'restricted_bucket', 'public')

      helmet_file = create_file('athena', 'helmet.jpg', HELMET, bucket: restricted_bucket, folder: public_folder)
      stubs.create_file('athena', 'restricted_bucket', 'public', 'helmet.jpg', HELMET)

      token_header(:viewer)
      json_post("/athena/find/restricted_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: 'w%'
      }])

      expect(last_response.status).to eq(403)
    end

    it 'returns no data if no search results found' do
      token_header(:viewer)
      json_post("/athena/find/my_bucket", params: [{
        attribute: 'name',
        predicate: '=~',
        value: 'private%'
      }])

      expect(last_response.status).to eq(200)
      expect(json_body[:files]).to eq([])
      expect(json_body[:folders]).to eq([])
    end
  end
end
