if exists("g:loaded_vimux_buster") || &cp
  finish
endif
let g:loaded_vimux_buster = 1

if !has("ruby")
  finish
end

command RunAllJavaScriptTests :call s:RunAllJavaScriptTests()
command RunJavaScriptFocusedTest :call s:RunJavaScriptFocusedTest()
command RunJavaScriptFocusedContext :call s:RunJavaScriptFocusedContext()

function s:RunAllJavaScriptTests()
  ruby JavaScriptTest.new.run_all
endfunction

function s:RunJavaScriptFocusedTest()
  ruby JavaScriptTest.new.run_test
endfunction

function s:RunJavaScriptFocusedContext()
  ruby JavaScriptTest.new.run_context
endfunction

ruby << EOF
module VIM
  class Buffer
    def method_missing(method, *args, &block)
      VIM.command "#{method} #{self.name}"
    end
  end
end

class JavaScriptTest
  def current_file
    VIM::Buffer.current.name
  end

  # Likely not needed with buster?
  def spec_file?
    current_file =~ /spec_|_spec/
  end

  def line_number
    VIM::Buffer.current.line_number
  end

  # Method to parse a string for a buster test
  # Returns test name or nil
  def parse_test_name(line)
    # Rudimentary test for key:value object member syntax + check for method sig
    line = line.split(":")
    return unless line.length && line[1] =~ /function/

    # So far so good! Parse out the test name (returned via magic var)
    line[0].scan(/([^"|']+)/)
    $1
  end

  def run_spec
    send_to_vimux("#{spec_command} '#{current_file}' -l #{line_number}")
  end

  def run_unit_test
    method_name = nil

    # Buster test format:
    # "STRING": function () { asserts... }
    # Pass method name as string to CLI
    #   e.g. buster test "foo"
    #   NOTE: treated as a RegExp for fuzzy matching
    #   Can't run test case (should be one per file anyway)
    (line_number + 1).downto(1) do |line_number|
      method_name = parse_test_name(VIM::Buffer.current[line_number])
      break if method_name
    end

    send_to_vimux("buster test --tests #{current_file} '#{method_name}'") if method_name
  end

  def run_test
    if spec_file?
      run_spec
    else
      run_unit_test
    end
  end

  def run_context
    method_name = nil
    context_line_number = nil

    (line_number + 1).downto(1) do |line_number|
      if VIM::Buffer.current[line_number] =~ /(context|describe) "([^"]+)"/ ||
         VIM::Buffer.current[line_number] =~ /(context|describe) '([^']+)'/
        method_name = $2
        context_line_number = line_number
        break
      end
    end

    if method_name
      if spec_file?
        send_to_vimux("#{spec_command} #{current_file} -l #{context_line_number}")
      else
        method_name = "\"/#{Regexp.escape(method_name)}/\""
        send_to_vimux("ruby #{current_file} -n #{method_name}")
      end
    end
  end

  def run_all
    if spec_file?
      send_to_vimux("#{spec_command} '#{current_file}'")
    else
      send_to_vimux("buster test -tests '#{current_file}'")
    end
  end

  def spec_command
    if File.exists?("Gemfile") && match = `bundle show rspec`.match(/(\d+\.\d+\.\d+)$/)
      match.to_a.last.to_f < 2 ? "bundle exec spec" : "bundle exec rspec"
    else
      system("rspec -v > /dev/null 2>&1") ? "rspec --no-color" : "spec"
    end
  end

  def send_to_vimux(test_command)
    Vim.command("call VimuxRunCommand(\"clear && #{test_command}\")")
  end
end
EOF