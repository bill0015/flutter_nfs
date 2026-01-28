Pod::Spec.new do |s|
  s.name             = 'flutter_nfs'
  s.version          = '0.1.0'
  s.summary          = 'High-performance NFS client for Flutter with zero-copy optimizations.'
  s.description      = <<-DESC
A Flutter plugin that provides zero-copy NFS file access powered by libnfs.
Ideal for game emulators loading ROMs from network storage.
                       DESC
  s.homepage         = 'https://github.com/my-org/flutter_nfs'
  s.license          = { :type => 'LGPL' }
  s.author           = { 'Bill' => 'bill@example.com' }
  s.source           = { :path => '.' }
  
  # Use shared sources from src/
  s.source_files = [
    'Classes/nfs_bridge.{c,h}',
    'Classes/FlutterNfsPlugin.{h,mm}',
    'Classes/block_cache.{cpp,hpp}',
    'Classes/libretro_vfs_impl.cpp'
  ]
  
  s.public_header_files = [
    'Classes/nfs_bridge.h',
    'Classes/FlutterNfsPlugin.h'
  ]
  
  # Use prebuilt libnfs
  s.vendored_libraries = 'lib/libnfs.a'
  
  # Link necessary system frameworks
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  
  s.library = 'c++'
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      '$(inherited)',
      '_DARWIN_C_SOURCE',
      'HAVE_NET_IF_H=1',
      'ENABLE_MULTITHREADING=1',
    ].join(' '),
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/../src/libnfs/include"',
      '"${PODS_TARGET_SRCROOT}/../src/libnfs/include/nfsc"',
      '"${PODS_TARGET_SRCROOT}/../src"',
    ].join(' '),
    'LIBRARY_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/lib"',
    ].join(' '),
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_LDFLAGS' => '-force_load "${PODS_TARGET_SRCROOT}/lib/libnfs.a"'
  }
  
  s.swift_version = '5.0'
end
