#
# Be sure to run `pod lib lint LocalResponse.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'LocalResponse'
  s.version          = '1.0.9'
  s.summary          = 'Mock iOS http API calls, without proxy and certificates, uses swizzling'
  s.swift_version    = '4.2'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Local response is a powerful developer tool for iOS developers, allowing you to intercept and mock network traffic in your iOS apps without the need for certificates or proxy configurations. This tool is a lightweight alternative to Proxyman and Charles Proxy, specifically designed for simplicity and ease of use.
                       DESC

  s.homepage         = 'https://github.com/chanonly123/local-response'
  s.screenshots      = 'https://github.com/chanonly123/local-response/raw/main/demo/demo2.gif'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Chandan Karmakar' => 'chan.only.123@gmail.com' }
  s.source           = { :git => 'https://github.com/chanonly123/local-response.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'Sources/LocalResponse/**/*.{swift}'

end
