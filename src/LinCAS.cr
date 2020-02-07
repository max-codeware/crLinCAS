
# Copyright (c) 2017-2018 Massimiliano Dal Mas
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "big"
require "option_parser"
require "colorize"

{% if flag?(:use_lp) %}
    ENV["libDir"] = File.expand_path("../lib",Dir.current)
{% else %}
    ENV["libDir"] = "/usr/local/lib/LinCAS/lib"
{% end %}

FFactory      = FrontendFactory.new
Compile       = Compiler.new
module LinCAS
    EOF = "\u0003"
    ALLOWED_FUNC_NAMES = 
    {
        TkType::PLUS, TkType::MINUS, TkType::STAR, TkType::SLASH, TkType::BSLASH,
        TkType::MOD, TkType::POWER, TkType::AND, TkType::OR, TkType::NOT, TkType::L_BRACKET, 
        TkType::EQ_EQ, TkType::GREATER, TkType::SMALLER, TkType::GREATER_EQ, 
        TkType::NOT_EQ, TkType::SMALLER_EQ,
        TkType::ASSIGN_INDEX, TkType::CLASS, TkType::UMINUS
    }
    {% if flag?(:x86_64)%}
      alias IntD  = Int64
      alias FloatD = Float64
    {% else %}
      alias IntD  = Int32
      alias FloaD = Float32
    {% end %}
    alias IntnumR  = Int32 | Int64
    alias Floatnum = Float32 | Float64
    {% if flag?(:fast_math) %}
        alias Intnum   = IntnumR
    {% else %}
        alias Intnum   = IntnumR | BigInt
    {% end %}
    alias Num  = Intnum  | Floatnum
    alias NumR = IntnumR | Floatnum

end

require "./Listeners"
require "./Message/Msg"
require "./Message/MsgType"
require "./Message/MsgGenerator"
require "./Message/MsgHandler"
require "./Frontend/Reader"
require "./Frontend/VirtualFile"
require "./Frontend/Source"
require "./Frontend/Scanner"
require "./Frontend/Token"
require "./Frontend/TokenDictConverter"
require "./Frontend/ErrorCode"
require "./Frontend/FrontendFactory"
require "./Frontend/ErrorHandler"
require "./Frontend/ParserDict"
require "./Frontend/Parser"
require "./Intermediate/NodeType"
require "./Intermediate/Nkey"
require "./Intermediate/Node"
require "./Intermediate/IntermediateFactory"
require "./Intermediate/Bytecode"
require "./Internal/MethodWrapper"
require "./Backend/Compiler"
require "./Prelude"
require "./Backend/VM"
require "../util/AstPrinter"
require "../util/Disassembler"


include LinCAS

tk_display   = false
ast_display  = false 
iseq_display = false
exec         = true

header = <<-Hd
Usage : lincas [options] [filename] [arguments]

options:
    -t  --tokens   Displays the tokens generated by the scanner
                   (the program won't be executed)
    -a  --ast      Displays the AST generated by the parser
    -i  --iseq     Displays the compiled bytecode
    -n  --no-exec  Suppresses the execution of the program
Hd

begin
    OptionParser.parse do |parser|
        parser.on("-t","--tokens") { tk_display   = true }
        parser.on("-a","--ast")    { ast_display  = true }
        parser.on("-i","--iseq")   { iseq_display = true }
        parser.on("-n","--no-exec"){ exec         = false}
        parser.on("-h","--help")   { puts header; exit 0 }
    end
rescue e 
    puts e.to_s.colorize(:red),
         header
    exit 1
end

dir = ARGV[0]?
if dir 
    begin
        at_exit do
            if Python.Py_IsInitialized
                Internal.lc_finalize
            end
        end
        Internal.lc_initialize
        parser = FFactory.makeParser(File.expand_path(dir))
        parser.noSummary # TODO: improving parsing time computation
        if tk_display
            parser.displayTokens
        end
        ast    = parser.parse
        if ast && parser.errCount == 0
            if ast_display
                ast_p = AstPrinter.new 
                ast_p.printAst(ast)
                puts
            end
            code   = Compile.compile(ast)
            if iseq_display
                iseq_p = Disassembler.new 
                iseq_p.disassemble(code)
                puts
            end
            Exec.run(code) if exec
        end
    rescue e
        LinCAS.lc_bug(e.inspect_with_backtrace)
    end
end