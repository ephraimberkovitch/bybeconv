#require "yaml"
desc "add/update two optional sections on all BY HTML files -- input file is assumed to be config/behead.payload off ROOT"
task :behead => :environment do
  thedir = AppConstants.base_dir
  tot = { :dir => 0, :files => 0, :new => 0, :upd => 0, :badenc => [] }
  # read payload data
  f = File.open('config/behead.payload', 'rb')
  usage if f.nil?

  payload = YAML::load(f.read) # read payload hash
  # convert the payload to Windows-1255, to match the HTML files.   fugly, I know...
  #payload['head'].encode!('windows-1255')
  #payload['body'].encode!('windows-1255')

  # traverse tree and process all HTML files
  behead_traverse(thedir, tot, payload)

  tot[:badenc].each {|f| print "#{f} has mixed encoding.\n" }
  print "\n#{tot[:dir]} directories containing #{tot[:files]} files scanned: #{tot[:new]} new files beheaded, #{tot[:upd]} files updated with new payload, #{tot[:badenc].count} files skipped due to mixed encoding.\n"
end

private
def usage
  print "behead.rb will add/update two optional 'payload' sections to the static BY HTML files.\n\nIt expects the payload input in a little YAML file called behead.payload in the current directory.\n\nThe file might look like this:\n\n---\nhead: |-\n  some payload\n  lines here\nbody: |-\n  more payload\n  lines here"
  die "missing param"
end
def behead_traverse(dir, t, payload)
  t[:dir]=t[:dir]+1
  print "traversing directory ##{t[:dir]} - #{dir}                \r"
  Dir.foreach(dir) { |fname|
    thefile = dir+'/'+fname
    if !(File.directory?(thefile)) and fname =~ /\.html$/ and not fname == 'index.html' and fname !~ /_no_nikkud/ and not dir == AppConstants.base_dir 
      t[:files] += 1 
      begin
        # fugly hack
        pre_read = File.open(thefile, 'rb').read(2000)
        if pre_read =~ /windows-1252/
          cp = 1252
          begin
            html = File.open(thefile, 'r:windows-1252:UTF-8').read
          rescue
            html = File.open(thefile, 'r:UTF-8').read
          end
        else
          cp = 1255
          html = File.open(thefile, 'r:windows-1255:UTF-8').read
        end
        orig_mtime = File.mtime(thefile)
        orig_atime = File.atime(thefile)
        unless has_placeholders?(html)
          html = insert_payload_placeholders(html) 
          t[:new] += 1
        else
          t[:upd] += 1
        end
        # keep a backup in case of catastrophe (e.g. power off) in the midst of live file update
        if cp == 1252
          wenc = 'w:UTF-8'
        else
          wenc = 'w:windows-1255'
        end
        File.open('behead.backup', wenc) { |f| 
          f.truncate(0)
          f.write(thefile + "\n")
          f.write(html)
        }
        newhtml = update_payload(html, payload)
        # DBG File.open("/tmp/__#{thefile.sub('/','_')}", 'w:windows-1255') { |f| 
        File.open(thefile, wenc) { |f| 
          f.truncate(0)
          f.write(newhtml) 
        }
        File.utime(orig_atime, orig_mtime, thefile) # restore (falsify, heh) previous mtime/atime to avoid throwing off date-based manual BY site updates
        # get rid of backup upon successful update.  This allows the _existence_ of the file to be a sign of trouble :)
      rescue
        puts "Bad encoding: #{thefile}"
        t[:badenc].push thefile
      end
      File.delete('behead.backup') if File.exist?('behead.backup')
    elsif File.directory?(thefile) and fname !~ /^_/ and fname !~ /[\._]files/ and fname !~ /^\./ and not AppConstants.populate_exclude.split(';').include? fname
      behead_traverse(thefile, t, payload) # recurse
    end
  }
end

def has_placeholders?(buf)
  return (buf.match(/<!-- begin BY head -->/)) && (buf.match(/<!-- begin BY body -->/))
end
def insert_payload_placeholders(buf)
  # insert section in HEAD
  m = buf.match(/<\/head>/)
  buf = $` + "<!-- begin BY head --><!-- end BY head -->" + $& + $'
  # insert section in BODY
  m = buf.match(/<body[^>]*>/)
  buf = $` + $& + "<!-- begin BY body --><!-- end BY body -->" + $'
  return buf
end
def update_payload(buf, payload)
  m = buf.match(/<!-- begin BY head -->/)
  tmpbuf = $` + $& + payload['head']
  m = buf.match(/<!-- end BY head -->/)
  tmpbuf += $& + $'
  m = tmpbuf.match(/<!-- begin BY body -->/)
  newbuf = $` + $& + payload['body']
  m = tmpbuf.match(/<!-- end BY body -->/)
  newbuf += $& + $'
  return newbuf
end

