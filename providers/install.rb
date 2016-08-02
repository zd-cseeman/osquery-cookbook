use_inline_resources

def whyrun_supported?
  true
end

action :install_ubuntu do
  os_version = node['platform_version'].split('.')[0].to_i
  os_codename = node['lsb']['codename']
  package_version = "#{new_resource.version}-1.ubuntu#{os_version}"

  apt_repository 'osquery' do
    action        :add
    uri           ::File.join(osquery_s3, os_codename)
    components    ['main']
    arch          'amd64'
    distribution  os_codename
    keyserver     'keyserver.ubuntu.com'
    key           repo_hashes[:ubuntu][:key]
    not_if { node['osquery']['repo']['internal'] }
    not_if { ::File.exist?('/etc/apt/sources.list.d/osquery.list') }
  end

  package 'osquery' do
    action   :install
    version  package_version
  end
end

action :install_centos do
  centos_version = node['platform_version'].split('.')[0].to_i
  package_version = "#{new_resource.version}-1.el#{centos_version}"
  repo_url = "#{osquery_s3}/centos#{centos_version}/noarch"
  centos_repo = "osquery-s3-centos#{centos_version}-repo-1-0.0.noarch.rpm"

  remote_file "#{file_cache}/#{centos_repo}" do
    action   :create
    source   "#{repo_url}/#{centos_repo}"
    checksum repo_hashes[:centos][centos_version]
    notifies :install, 'rpm_package[osquery repo]', :immediately
    not_if   { node['osquery']['repo']['internal'] }
  end

  rpm_package 'osquery repo' do
    action :nothing
    source "#{file_cache}/#{centos_repo}"
  end

  package 'osquery' do
    action   :install
    version  package_version
  end
end

action :install_os_x do
  domain = 'com.facebook.osqueryd'
  package_name = "osquery-#{new_resource.version}.pkg"
  package_url = "#{osquery_s3}/darwin/#{package_name}"
  package_file = "#{file_cache}/#{package_name}"

  remote_file package_file do
    action   :create
    source   package_url
    checksum mac_os_x_pkg_hashes[node['osquery']['version']]
    notifies :run, 'execute[install osquery]', :immediately
    only_if  { osx_upgradable }
  end

  directory '/var/log/osquery' do
    mode '0755'
  end

  execute 'install osquery' do
    action :nothing
    user 'root'
    command "installer -pkg #{package_file} -target /"
    notifies :run, 'execute[osqueryd permissions]', :immediately
  end

  execute 'osqueryd permissions' do
    command 'chown root:wheel /usr/local/bin/osqueryd'
    action :nothing
  end

  template "/Library/LaunchDaemons/#{domain}.plist" do
    source 'launchd.plist.erb'
    mode '0644'
    owner 'root'
    group 'wheel'
    variables(
      domain: domain,
      config_path: osquery_config_path,
      pid_path: '/var/osquery/osquery.pid'
    )
    notifies :restart, "service[#{domain}]"
  end
end

action :remove_ubuntu do
  apt_repository 'osquery' do
    action :remove
  end

  package 'osquery' do
    action :remove
    version "#{new_resource.version}-1.ubuntu#{os_version}"
  end
end

action :remove_centos do
  centos_version = node['platform_version'].split('.')[0].to_i
  package_version = "#{new_resource.version}-1.el#{centos_version}"

  package 'osquery' do
    action :remove
    version package_version
  end
end

action :remove_os_x do
  %w(osqueryi osqueryd osqueryctl).each do |osquery_bin|
    file osquery_bin do
      action :delete
    end
  end
end