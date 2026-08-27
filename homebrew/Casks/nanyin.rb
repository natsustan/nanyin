cask "nanyin" do
  version "0.1.1"
  sha256 "3fb033b1041e116c91b563c34c7a341a928b83509f18fcde0d8294c0ef272a15"

  url "https://github.com/natsustan/nanyin/releases/download/v#{version}/Nanyin-#{version}-arm64.dmg"
  name "Nanyin"
  desc "Native Spotify client powered by librespot"
  homepage "https://github.com/natsustan/nanyin"

  livecheck do
    url "https://github.com/natsustan/nanyin/releases/latest/download/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Nanyin.app"

  zap trash: [
    "~/Library/HTTPStorages/com.nanyin.app",
    "~/Library/Preferences/com.nanyin.app.plist",
  ]
end
