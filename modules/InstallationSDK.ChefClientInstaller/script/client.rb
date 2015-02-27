now = Time.new
log_level       :info
log_location    'c:/chef/client_' + now.strftime("%Y%m%d") + '.log'
cache_path      'c:\chef'
client_key      'c:\chef\client.pem'
