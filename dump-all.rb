#!/usr/bin/env ruby

require 'rotp'
require 'yaml'
require 'net/https'
require 'json'
require 'fileutils'
require 'pp'

class Hash
    def dump_to(account, file)
        json = JSON.pretty_generate(self)
        path = "#{File.dirname(__FILE__)}/dump/#{Time.now.strftime("%Y-%m-%d")}/#{account}/#{file}.json"
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'w') { |f| f.write(json) }
    end
end


def padding_zero(num, bits = 6)
    num = num.to_s
    while num.size < bits
        num = "0#{num}"
        return padding_zero(bits)
    end
    return num
end


def request_api(https, uri, totp, data = {})
    @http_request_opts['Cookie'] = @cookies.map{ |k, v| "#{k}=#{v}" }.join(';') unless @cookies.empty?
    requ = Net::HTTP::Post.new(uri, @http_request_opts)
    data['login_code'] = padding_zero(totp.now) unless totp.nil?
    requ.set_form_data(@common_data.merge(data))
    resp = https.request(requ)
    set_cookies = resp.to_hash['set-cookie']
    set_cookies.map{ |c| c[/^(.*?);/, 1] }.each do |cookie|
        key, val = cookie.split('=')
        @cookies = @cookies.merge({ key => val })
    end unless set_cookies.nil?
    json = JSON.parse(resp.body)
    $stderr.puts json['status']['message'] if json['status']['code'].to_i != 1
    return json
end

def get_login_code(secret_token)
    hotp = ROTP::HOTP.new("base32secretkey3232")
end

FileUtils.chdir(File.expand_path(File.dirname(__FILE__)))

uri = URI.parse('https://dnsapi.cn')
@https = Net::HTTP.new(uri.host, uri.port)
@https.use_ssl = true

@accounts = YAML::load_file('./accounts.yml')

@https.start do |https|
    @accounts.each do |account|
        @common_data = {
            'login_email'    => account['login_email'],
            'login_password' => account['login_passwd'],
            'format'         => 'json',
            'lang'           => 'cn',
            'error_on_empty' => 'no',
            'login_remember' => 'no'
        }
        @http_request_opts = { 'User-Agent' => 'XINDONG DNSPod Script' }
        @login_code = ARGV[0]
        @cookies = {}
        totp = ROTP::TOTP.new(account['secret_token']) if account.has_key?('secret_token')
        json = request_api(https, '/Domain.list', totp)
        json.dump_to(account['login_email'], "Domain.List")
        domain_total = json['info']['domain_total'].to_i
        break if domain_total == 0
        json['domains'].each do |domain|
            records = request_api(https, '/Record.List', totp, { 'domain_id' => domain['id'] })
            records.dump_to(account['login_email'], domain['name'])
        end
    end
end
