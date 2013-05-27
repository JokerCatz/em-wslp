#encoding:utf-8

$:.unshift(File.dirname(__FILE__) + '/../lib')

require "eventmachine"
%w[
  websocket
  connection
  handshake
  framing
  close
  masking
  message_processor
  handler
].each do |file|
  require "em-wslp/#{file}"
end


#gem merge from https://github.com/igrigorik/em-websocket
#version : 0.5.0 (a63dcfeb1e123ce0cbcd1de143f2dd1b4e44641f)
#minum and fixed
#license MIT