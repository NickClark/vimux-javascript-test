if exists("g:loaded_vimux_buster") || &cp
  finish
endif
let g:loaded_vimux_buster = 1

if !has("ruby")
  echohl ErrorMsg
  echon "Sorry, vimux-javascript-test requires vim +ruby support."
  finish
end

command RunJavaScriptTestSuite :call s:RunJavaScriptTestSuite()
command RunJavaScriptTestCase :call s:RunJavaScriptTestCase()
command RunJavaScriptFocusedTest :call s:RunJavaScriptFocusedTest()
" command RunJavaScriptFocusedContext :call s:RunJavaScriptFocusedContext()

function s:RunJavaScriptTestSuite()
  ruby JavaScriptTest.new.run_all
endfunction

function s:RunJavaScriptTestCase()
  ruby JavaScriptTest.new.run_file
endfunction

function s:RunJavaScriptFocusedTest()
  ruby JavaScriptTest.new.run_test
endfunction

" function s:RunJavaScriptFocusedContext()
"   ruby JavaScriptTest.new.run_context
" endfunction

" Buster user options
command BusterUseLocal :call s:BusterUseLocal()
command BusterUseGlobal :call s:BusterUseGlobal()
command! -nargs=* BusterSetGroup call s:BusterSetGroup(<f-args>)
command BusterSetGroupAll :call s:BusterSetGroup()

function! s:BusterUseLocal()
  let g:busterlocal = 1
endfunction

function! s:BusterUseGlobal()
  let g:busterlocal = 0
endfunction

function! s:BusterSetGroup(...)
  if a:0 > 0
    let g:bustergroup = a:1
  else
    let g:bustergroup = ""
  endif
endfunction

ruby << EOF
module VIM
  class Buffer
    def method_missing(method, *args, &block)
      VIM.command "#{method} #{self.name}"
    end
  end
end

# Semi-abstract runner interface
class Runner
  # should accept a buffer line number to parse from
  # should return a string
  def parse_test_name(line)
  end

  # should accept a filepath string and testname string
  def build_cmd(file = nil, testname = nil)
  end

  # Public: Obtains a Buster config group if specified by user
  #
  # Returns a config group string or Boolean false
  # Cleans out nested quotes from user input
  # Note: Zero is false in vimscript, so we return nil in that case
  def read_var(variable)
    exists = VIM::evaluate("exists('#{variable}')") != 0
    if (exists)
      val = VIM::evaluate(variable)
      val.gsub /\'|"/, "" if defined? val.gsub
      return val
    end
  end
end

# Public: Implements Runner interface for using Buster with vimux
class BusterRunner < Runner

  # Public: Parses the relevant test or spec name for a given line in buffer
  #
  # line  - The line contents to parse
  #
  # Returns a test name string
  def parse_test_name(line)
    # Early exclusions
    return if line =~ /setup|teardown|testCase/

    # To BDD, or TDD? Sorry.
    if line =~ /it\(/
      parts = line.split("it(")[1].split(",")
    else
      # Test for key:value object member syntax + check for method
      parts = line.split(":")
    end

    # Try and prevent false positives by checking for a function
    return unless parts.length && parts.last =~ /function/

    # Disco!
    parts.pop
    parts.join(":").scan(/([^"|']+)/)
    $1
  end


  # Public: Builds a test runner command to execute in the terminal with vimux
  #
  # file      - The JavaScript file to execute
  # testname  - The test to execute
  #
  # Returns a test name string
  def build_cmd(file = nil, testname = nil)
    cmd = []

    # buster executable
    if (read_var("g:busterlocal") != 0)
      cmd.push("./node_modules/.bin/buster-test")
    else
      cmd.push("buster test")
    end

    # Filter by file if applicable
    cmd.push("--tests '#{file}'") if file

    # Filter by test name if applicable
    cmd.push("'#{testname}'") if testname

    # Filter by group if applicable
    group = read_var("g:bustergroup");
    cmd.push("-g '#{group}'") if group

    return cmd.join(' ')
  end

end

# Public: Contains methods to map vimux-javascript commands into vimux input.
class JavaScriptTest

  def initialize
    @runner = createRunner
  end

  # Public: Returns filepath of buffer where command was executed upon
  def current_file
    VIM::Buffer.current.name
  end

  # Public: Returns location of cursor when command was executed in current buffer
  def line_number
    VIM::Buffer.current.line_number
  end

  # Public: Factory to create correct runner object to parse buffer
  def createRunner
    return BusterRunner.new if buster?
  end

  # Public: Conditional to detect if Buster.js is being used
  def buster?
    result = false
    # VIM::Buffer.current is a list *like* object, so no iteration
    # methods directly on the object (afaik)
    1.upto(VIM::Buffer.current.length) do |line_number|
      if VIM::Buffer.current[line_number] =~ /buster/
        result = true
        break;
      end
    end
    result
  end

  # Public: Executes contextual unit test if possible
  def run_test
    method_name = nil

    (line_number).downto(1) do |line_number|
      method_name = @runner.parse_test_name(VIM::Buffer.current[line_number])
      break if method_name
    end

    send_to_vimux(@runner.build_cmd(current_file, method_name)) if method_name
  end

  # Public: Executes the current file
  def run_file
    send_to_vimux(@runner.build_cmd(current_file))
  end

  # Public: Executes entire test suite
  def run_all
    send_to_vimux(@runner.build_cmd)
  end

  # Public: Sends command to vimux for execution in tmux shell
  def send_to_vimux(test_command)
    Vim.command("call VimuxRunCommand(\"clear && #{test_command}\")")
  end
end
EOF
