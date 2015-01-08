# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :minitest
Hoe.plugin :git
Hoe.plugin :travis

Hoe.spec 'http_connection_monitor' do
  developer 'Fastly, Inc.', 'ehodel@fastly.com'

  rdoc_locations << 'docs.seattlerb.org:/data/www/docs.seattlerb.org/http_connection_monitor/'

  license 'MIT'

  dependency 'capp', '~> 1.0'

  self.readme_file = 'README.rdoc'
end

namespace :travis do
  task :install_libpcap do
    sh 'sudo apt-get install libpcap-dev'
  end

  task before: %w[install_libpcap]
end

# vim: syntax=ruby
