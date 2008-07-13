require 'fileutils'

# INSTALL CONFIG FILE 
FileUtils.cp "#{File.dirname(__FILE__)}/example/last_fm.yml", "#{RAILS_ROOT}/config/last_fm.yml"

puts File.read("#{File.dirname(__FILE__)}/README")