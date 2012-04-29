Rails.application.config.middleware.use OmniAuth::Builder do
  require 'openid/store/filesystem'
  # load certificates
  require "openid/fetchers"
  OpenID.fetcher.ca_file = "#{Rails.root}/config/ca-bundle.crt"
  provider :facebook, 'APP_ID', 'APP_SECRET'
  #provider :twitter, 'CONSUMER_KEY', 'CONSUMER_SECRET'
  #provider :github, 'CLIENT ID', 'SECRET'
  provider :openid, :store => OpenID::Store::Filesystem.new('./tmp'), :name => 'openid'
  provider :openid, :store => OpenID::Store::Filesystem.new('./tmp'), :name => 'google', :identifier => 'https://www.google.com/accounts/o8/id'
#  provider :google_apps, OpenID::Store::Filesystem.new('/tmp'), :domain => 'benyehuda.org', :name => 'benyehuda'
  provider :openid, :store => OpenID::Store::Filesystem.new('./tmp'), :name => 'yahoo', :identifier => 'yahoo.com' 
  provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET']
end
