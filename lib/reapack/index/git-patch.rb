class ReaPack::Index::GitDiff < Git::Diff
private
  def cache_full
    super

    unless @full_diff.valid_encoding?
      @full_diff.encode! Encoding::UTF_8, invalid: :replace
    end
  end
end
