require 'asciidoctor/extensions'

include ::Asciidoctor

# Read from config file - do NOT hard code the srcdir
$srcdir = 'chapters'
invoc = Dir.pwd

AnchorRx = /\[\[(?:|([\w+?_:][\w+?:.-]*)(?:, *(.+))?)\]\]/

mains2, mainchaps, fixes, intrachapter, interchapter, titles, xrefs, dirs = [], [], [], [], [], [], [], []

adoc_files = Dir.glob("#{$srcdir}/**/*.adoc")

def trim(s)
  s = s.gsub(/^#{$srcdir}\//, '')
  s = s.gsub(/(\.adoc)/, '')
end

def underscorify(t)
  t = t.downcase.gsub(/(\s|-)/, '_')
  t = t.prepend('_') unless t.match(/^_/)
  t = t.gsub(/___/, '_').delete('`')
end

def titleify(t)
  t = t.gsub(/\_/, ' ')
  t = t.lstrip
  t = t.split.map(&:capitalize).join(' ')
end

# Read the index and create an array of the main chapters
File.read('index.adoc').each_line do |li|
  if li[IncludeDirectiveRx]
    doc = li.match(/(?<=^include::).+?\.adoc(?=\[\])/).to_s
    mains2.push(doc) unless doc == 'config'
  end
end

adoc_files.each do |filename|
  # ignore if not in directory referenced in index
  full = trim(filename)
  f = full.match(/.+?(?=\/)/).to_s
  dirs.push(f)
  chapter = f
  main = false

  mains2.each do |c|
    next unless c == filename
    main = true
  end

  File.read(filename).each_line do |li|
    h1 = false
    
    if li[/\<\<(?!Req)(.+?)\>\>/]
      li.scan(/(?=\<\<(?!Req)(.+?)\>\>)/) {|xref| 
        xref = xref[0].to_s
        text, target = '', ''
         if xref[/,/]
          target = xref.gsub(/,.+/, '').gsub(/\s/, '-')
          text = xref.gsub(/.+,/, '').lstrip
          xref = xref.sub(/,.+/, '')
        else
          target = xref.gsub(/\s/, '-')
          text = xref
        end
        item = [xref, full, filename, text, target, chapter]
        xrefs.push item
      }
    
    elsif li[/(^(\.\S\w+)|^(\=+\s+?\S+.+))/]
      h1 = true if li[/^=\s+?\S+.+/]
      title = li.chop.match(/(?!=+\s)(\S+.+?)$/i).captures[0]
      title.sub!(/\.(?=\w+?)/, '') if title[/\.(?=\w+?)/]
      title = title.strip   
      item = [title, full, filename, underscorify(title).strip, chapter, main, h1]
      titles.push item
    
    elsif li[InlineAnchorRx] || li[InlineAnchorScanRx] || li[BlockAnchorRx] || li[InlineSectionAnchorRx] || li[AnchorRx]
      anchor = li.chop.match(/(?<=\[\[).+?(?=\]\])/).to_s

      if anchor[/,/]
        anchor = anchor.match(/(?<=\[\[)(?:|[\w+?_:][\w+?:.-]*)(?=,.+?\]\])/).to_s
        text = anchor.sub(/.+?,/, '')
        text = text.sub(/\]\]$/, '')
      end
      item = [anchor, full, filename, text, chapter, main, h1, true]
      titles.push item
    end
  end
end

titles.each do |anchor, full, filename, text, chapter, main, h1|
  next unless main
  doc = full.gsub(/^#{chapter}\//, '')
  item = [chapter, doc, text, h1]
  mainchaps.push(item)
end

xrefs.each do |xref, xpath, xfile, xtext, xtarget, xchapter|
  titles.each do |ttext, tpath, tfile, alt, tchapter, main, h1, a|

    next unless ttext == xtext || ttext == xref || alt == xref || alt == xtarget
    xfile = trim(xfile)
    xtform = underscorify(xref) if xtform.to_s.empty?
    xtext = titleify(xtext) if xtext[/\_/]
    xtform = ttext if a

    if xchapter == tchapter
      fix = ["#{xtform},#{xtext}", xref]
    else
      mainchaps.each do |chapter, doc, text, h1|
        next unless tchapter == chapter && h1
        fix = ["#{text}##{xtform},#{xtext}", xref]
      end
    end

    fixes.push fix
  end
end

# dirs.delete_if { |a| a == '' }
# dirs.uniq!
# dirs.sort!

Extensions.register do
  preprocessor do
    process do |document, reader|
      Reader.new reader.readlines.map { |line|
        if line[/\<\<(?!Req)(.+?)\>\>/]  
          fixes.each do |fix, original|
            next unless line[/\<\<#{original}\>\>/]  
            line = line.sub(/\<\<#{original}\>\>/, "icon:exchange[] <<#{fix}>> ")
          end
        end
        line
      }
    end
  end
end
