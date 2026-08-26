cask "nanyin" do
  version "0.1.0"
  sha256 "40cbba84fd810d699d50276b1da769ba38bc3f29a7537c6cfe2121747285e9bb"

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
