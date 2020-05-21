describe Metis::CopyRevision do
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
      stubs.clear

      expect(stubs.contents(:athena)).to be_empty
    end

    it 'throws exception if nil dest provided' do
        expect {
            Metis::CopyRevision.new({
                dest: 'metis://athena/files/wisdom.txt'
            })
        }.to raise_error(Etna::BadRequest)
    end

    it 'throws exception for invalid dest path' do
        expect {
            Metis::CopyRevision.new({
                source: "metis://athena/files/wisdom.txt",
                dest: "metis://athena/files/learn\nwisdom.txt"
            }).to raise_error(Etna::BadRequest)
        }
    end
end