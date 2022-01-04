require "aws_billing2/version"

module AwsBilling2
  require 'aws-sdk-s3'
  require 'aws-sdk-costexplorer'
  require 'CSV'
  require 'text-table'
  require 'bigdecimal'
  require 'aws_billing2/record'
  require 'aws_billing2/main'
end
