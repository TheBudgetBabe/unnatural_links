# Fixup Unnatural Links

This is a script to trudge through mysql tables and update links in text to include `rel="nofollow"`.

*Note:* This was written with the [Serendipity Blog Platform](http://www.s9y.org) in mind (although it's 
pretty generic), so YMMV.  If you're going to use it, I suggest some local testing!

It will write out a log.html (which will probably be too big to open in a browser :)) and rollback.sql, 
which will include update statements to revert the fragments.  Don't rely on this!  _Please backup your database first!!_

## Requirements:

* mysql2 gem
* nokogiri gem
* differ gem
* htmlentities gem

## Usage

*I've been running this with ruby 2.4.0 and I don't plan to do any work to support anything else.  It
should work fine with any ruby >= 2.0, but you've been warned!*

* Update the file (no config or flags at this time!):
    * Mysql Client config:
    ```
    FishNiX::Fixer.new(client: Mysql2::Client.new(host: '127.0.0.1', username: 'root')).fix!
    ```
    * DATABASE, TABLES/COLUMNS (TABLE_COLS)
    * BLACKLIST_DOMAINS - domains/hosts to ignore
                                                    
* Run it!

## Known Limitations

* Works on one database at a time
