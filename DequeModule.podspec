Pod::Spec.new do |s|
    s.name = 'DequeModule'
    s.version = '1.1.4'
    s.license = { :type => 'Apache 2.0', :file => 'LICENSE.txt' }
    s.summary = 'Commonly used data structures for Swift'
    s.homepage = 'https://github.com/apple/swift-collections'
    s.author = 'Apple Inc.'
    s.source = { :git => 'https://github.com/lwt-sadais/swift-collections.git', :tag => s.version.to_s }
    s.documentation_url = 'https://github.com/apple/swift-collections'
    s.module_name = 'DequeModule'

    s.swift_version = '5.6'
    s.ios.deployment_target = '13.0'
    s.osx.deployment_target = '10.15'
    s.tvos.deployment_target = '17.0'
    s.visionos.deployment_target = '1.0'

    s.source_files = 'Sources/DequeModule/**/*.swift'
    s.dependency 'InternalCollectionsUtilities', s.version.to_s
end