require 'tempfile' 

ENCODING_SUBSTS = [{ :from => "\xCA", :to => "\xC9" }, # fix weird invalid chars instead of proper Hebrew xolams
    { :from => "\xFC", :to => "&uuml;"}, # fix u-umlaut
    { :from => "\xFB", :to => "&ucirc;"},
    { :from => "\xFF".force_encoding('windows-1255'), :to => "&yuml;"}] # fix u-circumflex


desc "Create the 'what's new?' table as an HTML fragment to be pasted into the site's (static) main page"
task :whatsnew, [:fromdate] => :environment do |taskname, args|
  args.with_defaults(:fromdate => (Date.today-30.days).to_s)
  print "args.fromdate seems to be #{args.fromdate}\n"
  known_authors = {}
  thedir = AppConstants.base_dir # environment-sensitive constant
  tot = { :dir => 0, :files => 0, :new => 0, :upd => 0 }
  newfiles = HtmlFile.new_since(Date.parse(args.fromdate).to_time)
  
  print "\n#{newfiles.count} new files found since #{args.fromdate}.\n"
  files_by_author = {}
  progress = 1
  newfiles.each { |h|
    relpath = h.path.sub(AppConstants.base_dir,'')
    authordir = relpath[1..-1].sub(/\/.*/,'')
    author = author_name_from_dir(authordir, known_authors)
    files_by_author[author] = [] if files_by_author[author].nil? # initialize array for author if first new work by that author
    print "DBG: trying to retrieve title from #{h.path}\n"
    files_by_author[author].push "<a href=\"#{relpath}\">#{HtmlFile.title_from_file(h.path)}</a>"
    print "\rHandled #{progress} files so far.     " #if progress % 10 == 0
    progress += 1
  }
  print "\nEmitting whatsnew.html... "
  dirs = known_authors.invert
  File.open("whatsnew.html", "w") {|f|
    f.write('<?xml version="1.0" encoding="utf8"?>\n<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\n<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="he"><body dir="rtl" align="right"><table>'+"\n")
    files_by_author.each {|a, files|
      #print "DBG: a = #{a}\n"
      #print "DBG: files = #{files.join('\; ')}\n"

      f.write("<tr><td><b><u>_______:</u></b> #{files.join('; ')}</td><td><a href=\"#{dirs[a]}/\">#{a}</a></td></tr>")
    }
    f.write("\n</table></body></html>")
  }
  print "done!\n"
end

private 

def fix_encoding(buf)
  # TODO: move to application.rb or something
  newbuf = buf.force_encoding('windows-1255')
      ENCODING_SUBSTS.each { |s|
        newbuf.gsub!(s[:from].force_encoding('windows-1255'), s[:to])
      }
  return newbuf
end 
def author_name_from_dir(d, known_authors)
  if known_authors[d].nil?
    thedir = HtmlDir.find_by_path(d)
    if thedir.nil?
      thedir = HtmlDir.new(:path => d, :author => "__edit__#{d}")
      thedir.save! # to be filled later
    end
    known_authors[d] = thedir.author
  end
  return known_authors[d]
end