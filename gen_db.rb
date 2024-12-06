require 'open3'
require 'json'

def major_minor_version(version)
  version.match(/^\d+\.\d+/)[0] + ".0"
end

def ruby_versions
  v3_1 = (0..6).map { |patch| "3.1.#{patch}" } + ['3.1.0-preview1']
  v3_2 = (0..6).map { |patch| "3.2.#{patch}" } + (1..3).map { |n| "3.2.0-preview#{n}" } + ['3.2.0-rc1']
  v3_3 = (0..5).map { |patch| "3.3.#{patch}" } + (1..3).map { |n| "3.3.0-preview#{n}" } + ['3.3.0-rc1']
  v3_1 + v3_2 + v3_3
end

def generate_ruby_code(ruby_version)
  <<~CODE
    require 'json'
    def get_info(pattern)
      path = Dir.glob(pattern).first
      json = {
        version: #{ruby_version.inspect},
        require_target: path,
        revision: RUBY_REVISION,
        size: File.size(path),
        mtime: File.mtime(path).to_i,
        compile_option: RubyVM::InstructionSequence.compile_option.inspect
      }
      JSON.dump(json)
    end
    puts get_info("/usr/local/lib/ruby/*/set.rb")
  CODE
end

def run_docker_command(ruby_version, code)
  command = ["docker", "run", "--rm", "ruby:#{ruby_version}-slim", "ruby", "-e", code]
  Open3.capture3(*command)
end

def process_version(db, ruby_version)
  code = generate_ruby_code(ruby_version)
  puts "RUNNING ON #{ruby_version}"

  stdout, stderr, status = run_docker_command(ruby_version, code)
  if status.success?
    puts "SUCCESS:\n#{stdout}"
    db << JSON.parse(stdout)
  else
    puts "ERROR:\n#{stderr}"
  end
end

def save_to_file(db, path)
  File.write(path, JSON.dump(db))
  puts "DB written to #{path}"
end

def main
  db = []
  ruby_versions.each do |ruby_version|
    process_version(db, ruby_version)
  end
  save_to_file(db, "ruby_database.json")
end

main

