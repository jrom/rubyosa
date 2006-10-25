# RDoc frontend for RubyOSA. Generate API referene documentation for the 
# given application, based on the descriptions in the sdef(5).
#
# Copyright (c) 2006, Apple Computer, Inc. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1.  Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer. 
# 2.  Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution. 
# 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
#     its contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission. 
# 
# THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'rbosa'
require 'tmpdir'

def usage
    STDERR.puts <<-EOS
Usage: #{$0} [--name | --path | --bundle_id | --signature] <criterion> [rdoc-options...]
Examples:
    # Generate HTML documentation for iTunes:
    #{$0} --name iTunes
    # Generate RI documentation for iTunes:
    #{$0} --name iTunes --ri
See rdoc --help for additional options.
EOS
    exit 1
end

def unique_tmp_path(base, extension='', dir=Dir.tmpdir)
   i = 0
   loop do
       p = File.join(dir, "#{base}-#{i}-#{Process.pid}" + extension)
       return p unless File.exists?(p)
       i += 1
   end
end

usage unless ARGV.length >= 2 

msg = case ARGV.first
    when '--name'
        :app_with_name
    when '--path'
        :app_with_path
    when '--bundle_id'
        :app_with_bundle_id
    when '--signature'
        :app_with_signature
    else
        usage
end

app = OSA.send(msg, ARGV[1])
mod = OSA.const_get(app.class.name.scan(/^OSA::(.+)::Application$/).to_s)
fake_ruby_src = mod.constants.map do |const_name|
    obj = mod.const_get(const_name)
    case obj
    when Class
        # Class.
        methods_desc = obj.const_get('METHODS_DESCRIPTION').map do |method|
            args_doc, args_def = '', ''
            if method.args and !method.args.empty?
                args_doc = method.args.map do |x| 
                    arg = x.name.dup
                    optional = arg.sub!(/=.+$/, '') != nil
                    "  # #{arg}::\n  #    #{x.description}" + (optional ? ' Optional.' : '')
                end.join("\n")
                args_def = '(' + method.args.map { |x| x.name }.join(', ') + ')'
            end
            if method.result
                args_doc << "\n" unless args_doc.empty?
                args_doc << "  # Returns::\n  #    #{method.result.description}\n"
            end
            <<EOS
  # #{method.description}
#{args_doc}
  def #{method.name}#{args_def}; end
EOS
        end
        <<EOS
# #{(obj.const_get('DESCRIPTION') || 'n/a')}
class #{obj.name} < #{obj.superclass}
#{methods_desc.join.rstrip}
end

EOS
    when Module
        # Enumeration group.
        next unless obj.const_defined?(:DESCRIPTION)
        enums_desc = obj.const_get(:DESCRIPTION).map do |item|
            <<EOS
  # #{item.description}
  #{item.name} = '#{obj.const_get(item.name).code}'
EOS
        end
        <<EOS
module #{mod.name}::#{const_name}
#{enums_desc}
end

EOS
    end
end.
join

fake_ruby_src = <<EOS + fake_ruby_src
# This documentation describes the RubyOSA API for the #{app.name} application. It has been automatically generated.
#
# For more information about RubyOSA, please visit the project homepage: http://rubyosa.rubyforge.org.
module OSA; end
# The #{app.name} module.
module #{mod.name}; end
EOS

path = unique_tmp_path(app.name, '.rb')
File.open(path, 'w') { |io| io.puts fake_ruby_src }
line = "rdoc #{ARGV[2..-1].join(' ')} \"#{path}\""
unless system(line)
    STDERR.puts "Error when executing `#{line}' : #{$?}"
    exit 1
end
File.unlink(path)
