#
# Cookbook Name:: cloudfoundry-distributed
# Recipe:: default
#


require 'digest/md5'

include_recipe "apt" 
include_recipe "git"

include_recipe "cloudfoundry::users"
include_recipe "cloudfoundry::rvm"

cloudfoundry_dir = "/home/#{node[:cloudfoundry][:user][:uid]}"

directory "#{cloudfoundry_dir}" do
  owner node[:cloudfoundry][:user][:uid]
  group node[:cloudfoundry][:user][:gid]
  action :create
end

git "#{cloudfoundry_dir}/vcap" do
  user node[:cloudfoundry][:user][:uid]
  repository "https://github.com/cloudfoundry/vcap.git"
  reference "master"
  action :sync
end 

gem_package "vmc"

# Setup vcap
%w(curl libcurl3 bison build-essential zlib1g-dev libssl-dev libreadline5-dev libxml2 libxml2-dev 
    libxslt1.1 libxslt1-dev git-core sqlite3 libsqlite3-ruby libsqlite3-dev unzip zip rake).each do |pkg|
  package pkg do
    action :install
  end
end

directory "/var/vcap" do
  mode 0777
end

%w(sys sys/log shared services).each do |dir|
  directory "/var/vcap/#{dir}" do
    owner node[:cloudfoundry][:user][:uid]
    recursive true
    mode 0777
  end
end

gem_package "bundler"

# Install DEA
%w(lsof psmisc librmagick-ruby python-software-properties curl java-common).each do |pkg|
  package pkg do
    action :install
  end
end

case node[:platform]
when "ubuntu","CentOS","RedHat","Fedora"
  %w(openjdk-6-jre).each do |pkg|
    package pkg do
      action :install
    end
  end
end

include_recipe "nodejs"

# Rubygems and support
%w(rack rake thin sinatra eventmachine).each do |gem_pkg|
  gem_package "#{gem_pkg}"
end

directory "/var/vcap.local" do
  recursive true
  mode 0777
end

# Secure directories
directory '/var' do
  mode 0755
end

%w(sys shared).each do |dir|
  directory dir do
    owner node[:cloudfoundry][:user][:uid]
    mode 0700
    recursive true
  end
end

directory "/var/vcap.local" do
  owner node[:cloudfoundry][:user][:uid]
  mode 0711
  recursive true
end

directory "/var/vcap.local/apps" do
  mode 0711
  recursive true
end

mbus_server = search(:node, 'role:mbus_server')[0]

template "#{cloudfoundry_dir}/vcap/dea/config/dea.yml" do
  source "dea.yml.erb"
  owner node[:cloudfoundry][:user][:uid]
  mode 0755
  variables({
    :local_route => "#{node[:ipaddress]}",
    :mbus_ip => "#{mbus_server[:ipaddress]}"
  })
end


Dir["#{cloudfoundry_dir}/vcap"].each do |dir|
  if File.directory?(dir)
    puts "Directory: #{dir}"
  end
end

execute "install bundler in #{node[:cloudfoundry][:rvm][:default_ruby]} the default ruby" do
  user "root"
  group 'rvm'
  command "rvm use #{node[:cloudfoundry][:rvm][:default_ruby]} && gem install bundler --no-ri --no-rdoc"
  not_if "rvm use #{node[:cloudfoundry][:rvm][:default_ruby]} | gem list | grep 'bundler'"
end

execute "Run rake bundler:install in vcap" do
  user "root"
  cwd "#{cloudfoundry_dir}/vcap/dea"
  command "rvm use #{node[:cloudfoundry][:rvm][:default_ruby]} && rake bundler:install"
  action :run
end

# This is because we are running as a lower user (kind of a hack)
directory "/tmp/vcap-run" do
  owner node[:cloudfoundry][:user][:uid]
  group node[:cloudfoundry][:user][:gid]
  action :create
end

execute "Start cloudfoundry dea" do
  user node[:cloudfoundry][:user][:uid]
  cwd "#{cloudfoundry_dir}/vcap"
  command "rvm use #{node[:cloudfoundry][:rvm][:default_ruby]} && bin/vcap start dea"
end
