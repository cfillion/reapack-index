class WordpressChangelog < MetaHeader::Parser
  CHANGELOG = /
    Changelog\s*:\n
    (.+?)\n\s*
    ((?:--)?\]\]|\*\/)
  /xm.freeze

  VERSION = /\A[\s\*]+v([\d\.]+)(?:\s+(.+))?\Z/.freeze

  def parse(input)
    input.encode! Encoding::UTF_8, invalid: :replace

    ver, changes = header[:version], header[:changelog]
    return if ver.nil? || changes || CHANGELOG.match(input).nil?

    $1.lines {|line| read line.lstrip }
  end

  def read(line)
    if line =~ VERSION
      @current = $1 == header[:version]
      line = $2.to_s
    end

    return unless @current

    if header[:changelog]
      header[:changelog] += "\n"
    else
      header[:changelog] = String.new
    end

    header[:changelog] += line.chomp
  end
end
