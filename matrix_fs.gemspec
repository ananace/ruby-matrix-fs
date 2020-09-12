require_relative 'lib/matrix_fs/version'

Gem::Specification.new do |spec|
  spec.name          = "matrix_fs"
  spec.version       = MatrixFS::VERSION
  spec.authors       = ["Alexander Olofsson"]
  spec.email         = ["ace@haxalot.com"]

  spec.summary       = "The poor man's distributed file system - over Matrix"
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/ananace/ruby-matrix-fs'
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  spec.extra_rdoc_files = %w[LICENSE.txt README.md]
  spec.files            = Dir['{bin,lib}/**/*'] + spec.extra_rdoc_files
  spec.executables      = 'mount.matrixfs'

  spec.add_development_dependency 'mocha'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'test-unit'

  spec.add_dependency 'matrix_sdk', '~> 2'
  spec.add_dependency 'rfusefs'
end
