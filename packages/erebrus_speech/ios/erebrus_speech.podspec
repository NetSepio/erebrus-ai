Pod::Spec.new do |s|
  s.name = 'erebrus_speech'
  s.version = '0.0.1'
  s.summary = 'On-device SpeechAnalyzer bridge for Erebrus AI.'
  s.homepage = 'https://erebrus.io'
  s.license = { :file => '../LICENSE' }
  s.author = { 'NetSepio' => 'contact@netsepio.com' }
  s.source = { :path => '.' }
  s.source_files = 'erebrus_speech/Sources/erebrus_speech/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
