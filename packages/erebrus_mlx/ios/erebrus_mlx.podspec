#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint erebrus_mlx.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'erebrus_mlx'
  s.version          = '0.0.1'
  s.summary          = 'Native MLX Swift inference backend for Erebrus AI.'
  s.description      = <<-DESC
Native MLX Swift inference backend for Erebrus AI.
                       DESC
  s.homepage         = 'https://erebrus.io'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NetSepio' => 'contact@netsepio.com' }
  s.source           = { :path => '.' }
  s.source_files = 'erebrus_mlx/Sources/erebrus_mlx/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'erebrus_mlx_privacy' => ['erebrus_mlx/Sources/erebrus_mlx/PrivacyInfo.xcprivacy']}
end
