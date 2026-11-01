Pod::Spec.new do |s|
  s.name = 'CoworkingView'
  s.version = '0.1.0'
  s.summary = 'Swift client for the CoworkingView Price Index and coworking catalogue.'
  s.description = <<-DESC
    CoworkingView is a Swift client for the public CoworkingView API at
    https://api.coworkingview.com. It reads the Price Index (median flexible-office
    prices by city and product, with the sample size beside every figure) and searches
    the coworking catalogue. No API key is required. Price Index data is from
    CoworkingView under CC BY 4.0. The code is MIT.
  DESC
  s.homepage = 'https://coworkingview.com'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'CoworkingView' => 'info@coworkingview.com' }
  s.source = {
    :git => 'https://github.com/coworkingview/coworkingview-swift.git',
    :tag => '0.1.0'
  }
  s.documentation_url = 'https://coworkingview.com/en/api'
  s.swift_versions = ['5.9', '6.0']
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'
  s.source_files = 'Sources/CoworkingView/**/*.swift'
  s.frameworks = 'Foundation'
end
