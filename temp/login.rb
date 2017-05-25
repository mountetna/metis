require 'net/http'
require 'openssl'
require 'base64'

#ENV['SSL_CERT_FILE'] = '/var/www/metis/temp/InCommon_CA_Intermediate.pem'

def log_in() 

  url = 'https://janus-stage.ucsf.edu/login'
  data = { 

    :email=> 'jason.cater@ucsf.edu', 
    :pass=> 'W4yn0w4y!', 
    :app_key=> 'ce6949c9a35f57edfb171f934f512d7b'
  }
  response = make_request(url, data)
end

def make_request(url, data)

  uri = URI.parse(url)

  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  
  https.verify_mode = OpenSSL::SSL::VERIFY_PEER

  #https.cert_store = OpenSSL::X509::Store.new
  #https.cert_store.set_default_paths
  #https.cert_store.add_file('./InCommon_CA_Intermediate.pem')

  #cert = OpenSSL::X509::Certificate.new(File.read('InCommon_CA_Intermediate.pem'))
  #encoded_content = File.read('./janus-stage_ucsf_edu_cert.cer')
  #decoded_content = Base64.decode64(encoded_content)
  #certificate = OpenSSL::X509::Certificate.new(decoded_content)
  #https.cert_store.add_cert(certificate)

  request = Net::HTTP::Post.new(uri.path)
  request.set_form_data(data)

  begin

    response = https.request(request)
    puts response.body.inspect

  rescue Timeout::Error, 
         Errno::EINVAL, 
         Errno::ECONNRESET, 
         EOFError, 
         Net::HTTPBadResponse, 
         Net::HTTPHeaderSyntaxError, 
         Net::ProtocolError => error

    met = __method__.to_s + ', '+ url +', '+ response_code.to_s
    puts met
  end
end

def check_certs()

  puts OpenSSL::OPENSSL_VERSION
  puts 'SSL_CERT_FILE: %s' % OpenSSL::X509::DEFAULT_CERT_FILE
  puts 'SSL_CERT_DIR: %s' % OpenSSL::X509::DEFAULT_CERT_DIR
end

log_in()