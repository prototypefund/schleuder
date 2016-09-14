require_relative 'lib/schleuder.rb'

load "active_record/railties/databases.rake"

# Configure ActiveRecord
ActiveRecord::Tasks::DatabaseTasks.tap do |config|
  config.root = File.dirname(__FILE__)
  config.db_dir = 'db'
  config.migrations_paths = ['db/migrate']
  config.env = ENV['SCHLEUDER_ENV']
  config.database_configuration = Schleuder::Conf.databases
end

# ActiveRecord requires this task to be present
Rake::Task.define_task("db:environment")

task :console do
  exec "irb -r #{File.dirname(__FILE__)}/lib/schleuder.rb"
end

version = Schleuder::VERSION
tagname = "schleuder-#{version}"
tarball = "#{tagname}.tar.gz"
gpguid = 'schleuder2@nadir.org'

desc 'Release a new version of schleuder.'
task :release => [:git_tag, :gem, :publish_gem, :tarball, :wiki]

task :gem => :check_version
task :git_tag => :check_version
task :tarball => :check_version

desc "Build new version: git-tag and gem-file"
task :build => [:gem, :edit_readme, :git_commit, :git_tag] do

end

desc "Edit README"
task :edit_readme do
  if system('gvim -f README.md')
    `git add README.md`
  else
    exit 1
  end
end

desc 'git-tag HEAD as new version'
task :git_tag do
  `git tag -u #{gpguid} -s -m "Version #{version}" #{tagname}`
end

desc "Commit changes as new version"
task :git_commit do
  `git commit -m "Version #{version} (README, gems)"`
end

desc 'Build, sign and commit a gem-file.'
task :gem do
  gemfile = "#{tagname}.gem"
  `gem build schleuder.gemspec`
  `mv -iv #{gemfile} gems/`
  `cd gems && gpg -u #{gpguid} -b #{gemfile}`
  `git add gems/#{gemfile}*`
end

desc 'Publish gem-file to rubygems.org'
task :publish_gem do
  `gem push #{tagname}.gem`
end

desc 'Build and sign a tarball'
task :tarball do
  `git archive --format tar.gz --prefix "#{tagname}/" -o #{tarball} #{tagname}`
  `gpg -u schleuder2@nadir.org --detach-sign #{tarball}`
end

desc 'Describe manual wiki-related release-tasks'
task :wiki do
  puts "Please update the website:
  * Upload tarball+signature.
  * Edit download- and changelog-pages.
  * Publish release-announcement.
"
end

desc 'Check if version-tag already exists'
task :check_version do
  # Check if Schleuder::VERSION has been updated since last release
  if `git tag`.include?(tagname)
    $stderr.puts "Warning: Tag '#{tagname}' already exists. Did you forget to update schleuder/version.rb?"
    $stderr.print "Continue? [yN] "
    if ! $stdin.gets.match(/^y/i)
      exit 1
    end
  end
end

