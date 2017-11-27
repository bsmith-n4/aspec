require 'asciidoctor/extensions' unless RUBY_ENGINE == 'opal'

include ::Asciidoctor

$srcdir = 'chapters'
adoc_files = Dir.glob("#{$srcdir}/**/*.adoc")

docs, doclinks, fixes, titles, mainchaps, reqs, indexincludes, xrefs = [], [], [], [], [], [], [], [], []

# remove source directory and file extension
def trim(s)
  s = s.gsub(/^#{$srcdir}\//, '')
  s = s.gsub(/(\.adoc)/, '')
end

def underscorify(t)
  t = t.downcase.gsub(/(\s|-)/, '_')
  t = t.prepend('_') unless t =~ /^_/
  t = t.gsub(/___/, '_').delete('`')
end

# create somd Display Text if none provided
def titleify(t)
  t = t.tr('_', ' ')
  t = t.lstrip
  t = t.split.map(&:capitalize).join(' ')
end

# Read the index and create an array of the main chapters
File.read('index.adoc').each_line do |li|
  if li[IncludeDirectiveRx]
    doc = li.match(/(?<=^include::).+?\.adoc(?=\[\])/).to_s
    indexincludes.push(doc) unless doc == 'config'
  end
end

includes = []

adoc_files.each do |filename|
  main = false
  chapter = trim(filename).match(/.+?(?=\/)/).to_s

  indexincludes.each do |c|
    next unless c == filename
    main = true
  end

  # Create small array of chapter and contained docs
  docs.push([filename.sub(/^#{$srcdir}\//, ''), chapter])

  File.read(filename).each_line do |li|
    # Match Requirement Blocks [req,ABC-123,version=n]
    if li[/\[\s*req\s*,\s*id\s*=\s*(\w+-?[0-9]+)\s*,.*/]

      rid = li.chop.match(/id\s*=\s*(\w+-?[0-9]+)/i).captures[0]
      path = filename.sub(/^#{$srcdir}\//, '')
      item = [rid, li.chop, trim(path), filename, main, chapter]
      reqs.push item

    # Match xrefs to Requirements <<Req->>
    elsif li[/\<\<Req-.+?(\,\S)?\>\>/]

      xid = li.chop.match(/(?<=<<Req-).+?(?=>>)/i).to_s
      xref = li.chop.match(/\<\<(\S.+?)(\,\S)?\>\>/i)
      path = filename.sub(/^#{$srcdir}\//, '')
      item = [xref, path, filename, main, chapter, xid]
      xrefs.push item

    elsif li[/(^(\.\S\w+)|^(\=+\s+?\S+.+))/]
      h1 = true if li[/^=\s+?\S+.+/]

      title = li.chop.match(/(?!=+\s)(\S+.+?)$/i).captures[0]
      title.sub!(/\.(?=\w+?)/, '') if title[/\.(?=\w+?)/]
      title = title.strip
      item = [title, trim(filename), filename, underscorify(title).strip, chapter, main, h1]
      titles.push item

    elsif li[IncludeDirectiveRx]
      child = li.match(/(?<=^include::).+?\.adoc(?=\[\])/).to_s
      childpath = "#{filename.sub(/[^\/]+?\.adoc/, '')}#{child}"
      includes.push([filename, child, childpath])

    end
  end
end

# For each main include, calculate a H1
titles.each do |_anchor, full, _filename, text, chapter, main, h1|
  next unless main
  doc = full.gsub(/^#{chapter}\//, '')
  item = [chapter, doc, text, h1]
  mainchaps.push(item)
end

# Calculate the permalink for all documents within a chapter
mainchaps.each do |mchapter, doc, link, h1|
  next unless h1
  # puts "Creating h1 link #{link} for #{mchapter}/#{doc}"
  item = [doc, link, mchapter]
  doclinks.push(item)
end

ssincs = []
ni_includes = []

# Create array of non-indexed includes
adoc_files.each do |filename|
  includes.each do |parent, child, childpath|
    # puts "Regular l1include is  #{parent} #{child} , #{childpath}"
    next unless childpath == filename
    # puts "PUSHING #{parent} #{filename} , #{filename}"
    ni_includes.push([parent, child, filename])
  end
end

includes += ni_includes

tempreqs = []

2.times do
  puts ''
  puts ''
  includes.each do |parent, _child, childpath|
    reqs.delete_if do |rid, line, path, filename, main, chapter|
      puts "ThisReq : #{rid} in #{path} and #{filename}"
      puts "Checking if #{trim(childpath)} == #{trim(path)}"
      next unless trim(childpath) == path
      puts "+++++++++ Snap, modifying this req to be #{rid}, #{parent}"
      tempreqs.push([rid, line, parent, filename, main, chapter])
      true
    end
  end
  reqs += tempreqs
end

# Check if the requirement is in an include, if so, point to parent doc
includes.each do |parent, _child, childpath|
  # puts ""
  # puts "Checking #{child}, #{childpath} -> should link to #{parent}"
  # Calculate the permalink for all documents within a chapter
  mainchaps.each do |mchapter, doc, link, _h1|
    # puts "checking if #{mchapter}/#{doc} == #{trim(parent)}"
    next unless trim(parent) == "#{mchapter}/#{doc}"
    # puts "BOOM Creating h1 link #{link} for #{mchapter}/#{trim(childpath)}"
    item = [doc, link, trim(childpath).to_s]
    doclinks.push(item)
  end
end

# Sort (in-place) by numberic ID
reqs.sort_by!(&:first)

# Calculate what document each requirement should point to and add which chapter they are currently in
reqs.each do |rid, _line, path, _filename, _main, _chapter|
  doclinks.each do |_doc, link, chapter|
    puts "CHECKING #{chapter} is same as #{path}"
    next unless chapter == path
    puts "BOOOM MATCHED #{rid} is in file #{link}"
    fix = [rid, link]
    puts "Fix for #{rid} is #{link}"
    fixes.push(fix)
    break
  end
end

# Match for overridden titles - (?x)\[\[.+?\]\]\n=\s{1,}.+$
# i.e. :
#
# [[Some-overriding-anchor]]
# = Section 1 level title

# adoc_files.each do |filename|

Extensions.register do
  inline_macro do
    named :reqlink

    # Regex-based, will match "See Req-ROPR-123 for..."
    match /(Req-\w+-?\d+)/

    # match id with  Req-\w+-?(\d+)
    process do |parent, target|
      # docname = parent.parent.document.attributes['docname']

      # puts parent.parent.document.attributes
      # puts ""
      id = target.sub(/^Req-/, '')
      # puts "This req #{id} is in #{docname}"
      fix = ''

      fixes.each do |fixid, file|
        fix = file if fixid == id
      end

      link = target.sub(/^Req-/, '')
      uri = "#{fix}.html##{link}"
      uri = "##{link}" if fix == ''
      o = '<span class="label label-info">'
      c = '</span> '
      (create_anchor parent, %(#{o} Req. #{id} #{c}), type: :link, target: uri).convert
    end
  end
end
