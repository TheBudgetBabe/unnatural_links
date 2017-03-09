#!/usr/bin/env ruby
# Basic script to trudge through mysql data and add
# 'rel="nofollow"' to all of the links

require 'awesome_print'
require 'mysql2'
require 'nokogiri'
require 'uri'
require 'logger'
require 'differ'
require 'erb'
require 'htmlentities'

DATABASE = 'exampledb'
TABLE_COLS = { serendipity_entries: ['body', 'extended'] }
BLACKLIST_DOMAINS = [
    'example.com',
    'www.example.com'
]

LOG_LEVEL = Logger::WARN

module FishNiX
  class Fixer
    def initialize(options)
      @client = options[:client]
      @client.select_db(DATABASE)
      @dryrun = options[:dryrun]
      @logger = options[:logger]
      @links = 0
      @processed_links = []
      @fragments = 0
      @processed_fragments = 0
      @statements = []
    end

    # Start the fix!
    def fix!
      TABLE_COLS.each do |table, cols|
        cols.each do |column|
          # Query mysql and loop over there result set
          @client.query(select_sql table: table, column: column).each do |result|
            next if result[column] == ''
            @fragments += 1
            id = result['id']
            raise 'ID cannot be nil!' if id.nil?
            begin
              @logger.debug('Selecting links from document fragment for id: ' + id.to_s)
              frag = doc(result[column])
              new_frag = process(frag.clone)
              next if frag.to_s == new_frag.to_s

              unless @dryrun
                update!(table: table, column: column, id: id, new_frag: new_frag.to_s, old_frag: frag.to_s)
                @processed_fragments += 1
              end
            rescue => e
              @logger.error('Something went wrong processing fragment! (' + e.to_s + ')')
            end
          end
        end
      end

      flush_statements
      write_log
    end

    # Parse the given fragment and return the Nokogiri object
    def doc(txt)
      @logger.debug('Parsing document fragement: ' + txt)
      Nokogiri::HTML::DocumentFragment.parse(txt)
    end

    # Look for the 're="nofollow"' attribute
    def nofollow?(link)
      @logger.debug('Checking link for nofollow')
      !link[:rel].nil? && link[:rel] == 'nofollow'
    end

    # Check if the host component of the href is in the blacklist
    def blacklist?(link)
      @logger.debug('Checking blacklist.')
      begin
        host = URI.parse(link[:href]).host.downcase
        host.downcase!
        @logger.debug('Parsed host from link: ' + host)
        BLACKLIST_DOMAINS.include?(host)
      rescue => e
        @logger.warn('Failed checking blacklist for: "' + link.to_s + '" (' + e.to_s + ')')
      end
    end

    # process the fragment
    def process(frag)
      frag.css('a').each do |link|
        @logger.debug('Processing link: "' + link.to_s + '"')
        @links += 1
        next if nofollow?(link)
        next if blacklist?(link)
        old = link.to_s
        link.set_attribute('rel', "nofollow #{link.attribute('rel')}".strip)
        diff(old, link.to_s)
        @logger.debug('Converting link from: "' + old + '" to "' + link.to_s + '"')
      end
      frag
    end

    def update!(opts = {})
      @statements.push(opts)
      flush_statements if @statements.length >= 100
    end

    def flush_statements
      File.open('rollback.sql', 'a') do |file|
        @statements.each do |f|
          s = update_sql(frag: f[:new_frag], table: f[:table], column: f[:column], id: f[:id])
          @logger.debug('Updating database with SQL: ' + s)
          @client.query(s)

          r = update_sql(frag: f[:old_frag], table: f[:table], column: f[:column], id: f[:id])
          @logger.debug('Writing rollback sql: ' + s)
          file.write("#{r}\n")
        end
      end

      @statements = []
    end

    def select_sql(opts = {})
      "select id, #{opts[:column]} from #{opts[:table]}"
    end

    def update_sql(opts)
      escaped = @client.escape(opts[:frag])
      "UPDATE #{opts[:table]} SET #{opts[:column]} =\"#{escaped}\" where id = #{opts[:id]};"
    end

    def diff(old, new)
      d = Differ.diff_by_word(old, new)
      puts d.format_as(:color)
      @processed_links.push(HTMLEntities.new.encode d)
    end

    def write_log
      out = ::ERB.new(File.read('logfile.html.erb'))
      File.open('log.html', 'w') do |f|
        f.write out.result(binding)
      end
    end
  end
end

logger = Logger.new(STDOUT)
logger.level = LOG_LEVEL
FishNiX::Fixer.new(client: Mysql2::Client.new(host: '127.0.0.1', username: 'root'), logger: logger).fix!
