# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

def shared_pods
  pod 'GoogleWebRTC'
  pod 'Socket.IO-Client-Swift'
end

target 'ScreenShareApp' do
  use_frameworks!
  shared_pods
end

target 'ScreenShareExt' do
  use_frameworks!
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    end
  end
end
