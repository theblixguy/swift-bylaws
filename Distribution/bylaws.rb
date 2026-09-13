class Bylaws < Formula
  desc "Architectural linter for Swift projects using Bylaws.swift rules"
  homepage "https://github.com/theblixguy/swift-bylaws"
  url "{{ARTIFACT_BUNDLE_URL}}"
  version "{{VERSION}}"
  sha256 "{{ARTIFACT_BUNDLE_SHA256}}"
  license "MIT"

  on_linux do
    depends_on arch: :x86_64
  end

  on_macos do
    depends_on macos: :sonoma
  end

  def install
    platform = OS.mac? ? "macos" : "linux"
    bin.install "#{platform}/bin/bylaws"
    bin.install "#{platform}/bin/bylaws-lsp"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/bylaws --version").strip
    assert_equal version.to_s,
                 shell_output("#{bin}/bylaws-lsp --version").strip
    system bin/"bylaws", "init"
    assert_match "let app = Codebase", (testpath/"Bylaws.swift").read
  end
end
