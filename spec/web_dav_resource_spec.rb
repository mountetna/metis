describe Metis::WebDavResource do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  after(:each) do
    stubs.clear
  end

  let(:project_name) { 'labors' }
  let(:other_project_name) { 'sports' }
  let(:bucket_name) { 'files' }
  let(:other_bucket_name) { 'files' }
  let!(:bucket) { default_bucket(project_name, bucket_name: bucket_name) }
  let!(:other_bucket) { default_bucket(other_project_name, bucket_name: other_bucket_name) }
  let!(:location) { stubs.create_file(project_name, bucket_name, file_name, contents) }
  let(:contents) { "1. Burn the hydra's neck after cutting.\n2. Use a river to clean the stables." }
  let(:file_name) { 'readme_hercules.txt' }
  let(:file) { create_file(project_name, file_name, contents, bucket: bucket) }
  let(:hmac_params) { {} }
  let(:params) { {} }
  let(:env) { {} }
  let(:project_role) { :admin }
  let(:other_project_role) { :viewer }
  let(:permissions) { [[project_name, project_role], [other_project_name, other_project_role]] }
  let(:user) { {email: 'zeus@olympus.org', first: 'Zeus', perm: permissions.map { |project, r| "#{r.to_s[0,1]}:#{project}" }.join(',')} }
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

  subject do
    # token = application.sign.jwt_token(user)
    token = Base64.strict_encode64(user.to_json)
    auth = Base64.strict_encode64("user:#{token}")
    header('Authorization', "Basic #{auth}")

    custom_request(method, path, params, env)
    last_response
  end

  def response_xml
    @response_xml ||= Nokogiri.XML(last_response.body) { |config| config.strict }
  end

  describe 'fetching projects' do
    let(:path) { '/webdav/projects/' }
    let(:method) { 'PROPFIND' }
    let(:env) { {'HTTP_DEPTH' => '1', input: propfind_xml} }

    it 'does a thing' do
      expect(subject.status).to eq(207)
      response_xml.xpath('//d:multistatus/d:response').each do |response|
        propstat = response.xpath('//d:propstat').first
        expect(propstat.xpath('//d:status').first.text).to match(/200 OK/)
      end

      response = response_xml.xpath('//d:multistatus/d:response').last
      hrefs = response.xpath('//d:href').map(&:text).map { |href| URI.parse(href).path }
      expect(hrefs).to eq([])
    end
  end

  # it 'downloads a file' do
  #   hmac_header
  #   get('/labors/download/files/readme_hercules.txt')
  #   expect(last_response.status).to eq(200)
  #   # normally our web server should catch this header and replace the
  #   # contents; we can't do that with Rack::Test
  #   expect(last_response.headers['X-Sendfile']).to eq(@location)
  # end
end
