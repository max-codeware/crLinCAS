# Copyright (c) 2020 Massimiliano Dal Mas
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

{% begin %}
  
  {{list = %w|
    Misc
    Token
    Reader
    Lexer
    Node
    Parser
  |}}

  {% for name in list %}
    require "./#{{{name}}}"
  {% end %}

{% end %}

file = File.read("../../test/Sintax/Token.lc")
read = Char::Reader.new(file)
lex = LinCAS::Lexer.new(read)

while (tk = lex.next_token).type != LinCAS::Tk::EOF
  loc = tk.location 
  puts tk
end