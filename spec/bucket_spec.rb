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
      bucket2 = create( :bucket, project_name: 'athena', name: 'extra', access: 'viewer', owner: 'metis' )

      token_header(:viewer)
      get('/athena/list')

      expect(last_response.status).to eq(200)

      expect(json_body[:buckets]).to eq(Metis::Bucket.all.map(&:to_hash))
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
      expect(json_body[:error]).to eq('Invalid bucket')
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
      json_post('/athena/bucket/update/my_bucket', owner: 'athena', access: 'viewer', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      expect(bucket.name).to eq('my_bucket')
      expect(bucket.owner).to eq('athena')
      expect(bucket.access).to eq('viewer')
      expect(bucket.description).to eq('My Bucket')

      expect(last_response.status).to eq(200)
      expect(json_body[:bucket]).to eq(bucket.to_hash)
    end

    it 'requires a legal owner' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', owner: 'outis', access: 'viewer', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      expect(bucket.name).to eq('my_bucket')
      expect(bucket.owner).to eq('metis')
      expect(bucket.access).to eq('editor')
      expect(bucket.description).to be_nil

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid owner')
    end

    it 'requires a legal access' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')

      token_header(:admin)
      json_post('/athena/bucket/update/my_bucket', owner: 'metis', access: 'casual', description: 'My Bucket')

      # the record remains
      bucket.refresh
      expect(Metis::Bucket.all).to eq([bucket])

      expect(bucket.name).to eq('my_bucket')
      expect(bucket.owner).to eq('metis')
      expect(bucket.access).to eq('editor')
      expect(bucket.description).to be_nil

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid access')
    end
  end

  context '#remove' do
    it 'requires an existing bucket' do
      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(422)
      expect(json_body[:error]).to eq('Invalid bucket')
    end

    it 'requires admin permissions' do
      token_header(:editor)
      delete('/athena/bucket/remove/my_bucket')

      expect(Metis::Bucket.count).to eq(0)
      expect(last_response.status).to eq(403)
    end

    it 'removes a bucket' do
      bucket = create( :bucket, project_name: 'athena', name: 'my_bucket', access: 'editor', owner: 'metis')
      stubs.create_bucket('athena', 'my_bucket')

      token_header(:admin)
      delete('/athena/bucket/remove/my_bucket')

      expect(last_response.status).to eq(200)
      expect(Metis::Bucket.count).to eq(0)
      expect(File.exists?(bucket.location)).to be_falsy
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
end
