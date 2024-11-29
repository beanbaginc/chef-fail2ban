#
# Cookbook:: fail2ban
# Recipe:: default
#
# Copyright:: 2009-2018, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# epel repository is needed for the fail2ban package on rhel
if node['fail2ban']['install_source']
  fail2ban_version = node['fail2ban']['source_version']
  fail2ban_zip_basename = "fail2ban-#{fail2ban_version}.zip"
  fail2ban_zip = "#{Chef::Config[:file_cache_path]}/#{fail2ban_zip_basename}"

  remote_file fail2ban_zip do
    action :create
    source "https://github.com/fail2ban/fail2ban/archive/refs/tags/#{fail2ban_version}.zip"
    checksum node['fail2ban']['source_checksum']
    owner 'root'
    group 'root'
    mode '0644'
  end

  bash 'compile-fail2ban' do
    cwd Chef::Config[:file_cache_path]
    code <<-EOF
      unzip #{fail2ban_zip_basename}
      cd fail2ban-#{fail2ban_version}
      python3 setup.py install --prefix=/usr
      cp build/fail2ban.service /etc/systemd/system/
    EOF
    creates '/usr/bin/fail2ban-client'
  end
else
  include_recipe 'yum-epel' if node['fail2ban']['install_epel']

  package node['fail2ban']['package_name'] do
    action :install
    notifies :reload, 'ohai[reload package list]', :immediately
  end
end

if node['fail2ban']['slack_webhook']
  package 'curl' do
    action :install
    notifies :reload, 'ohai[reload package list]', :immediately
  end
end

ohai 'reload package list' do
  plugin 'packages'
  action :nothing
end

node['fail2ban']['filters'].each do |name, options|
  template "/etc/fail2ban/filter.d/#{name}.conf" do
    source 'filter.conf.erb'
    variables(
      failregex: [options['failregex']].flatten,
      ignoreregex: [options['ignoreregex']].flatten
    )
    notifies :restart, 'service[fail2ban]'
  end
end

template '/etc/fail2ban/fail2ban.conf' do
  source 'fail2ban.conf.erb'
  notifies :restart, 'service[fail2ban]'
end

template '/etc/fail2ban/jail.local' do
  source 'jail.conf.erb'
  variables(
    slack_webhook: node['fail2ban']['slack_webhook']
  )
  notifies :restart, 'service[fail2ban]'
end

if node['fail2ban']['slack_webhook']
  template '/etc/fail2ban/action.d/slack.conf' do
    source 'slack.conf.erb'
    notifies :restart, 'service[fail2ban]'
  end

  template '/etc/fail2ban/slack_notify.sh' do
    source 'slack_notify.sh.erb'
    owner 'root'
    group 'root'
    mode '0750'
    variables(
      slack_channel: node['fail2ban']['slack_channel'],
      slack_webhook: node['fail2ban']['slack_webhook']
    )
    notifies :restart, 'service[fail2ban]'
  end
end

file '/etc/fail2ban/jail.d/defaults-debian.conf' do
  action 'delete'
  only_if { platform?('ubuntu') }
end

file '/etc/fail2ban/jail.d/00-firewalld.conf' do
  action 'delete'
  only_if { platform?('centos') }
end

service 'fail2ban' do
  supports [status: true, restart: true]
  action [:enable, :start] if platform_family?('rhel', 'amazon', 'fedora')
  action [:enable] if platform_family?('debian', 'suse')
end
