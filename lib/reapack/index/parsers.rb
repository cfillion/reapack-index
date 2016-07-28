class WordpressChangelog < MetaHeader::Parser
  CHANGELOG = /
    Changelog\s*:\n
    (.+?)\n\s*
    ((?:--)?\]\]|\*\/)
  /xm.freeze

  VERSION = /\A[\s\*]*v([\d\.]+)(?:\s+(.+))?\Z/.freeze

  def parse(input)
    input = input.read
    input.encode! Encoding::UTF_8, invalid: :replace

    ver, changes = header[:version], header[:changelog]
    return if ver.nil? || changes || CHANGELOG.match(input).nil?

    $1.lines.each {|line| read line.lstrip }
  end

  def read(line)
    if line =~ VERSION
      @current = $1 == header[:version]
    elsif @current
      if header[:changelog]
        header[:changelog] += "\n"
      else
        header[:changelog] = String.new
      end

      header[:changelog] += line.chomp
    end
  end
end
