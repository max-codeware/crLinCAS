
# Copyright (c) 2017 Massimiliano Dal Mas
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

class LinCAS::ErrorHandler

    MAX_ERR = 10

    def initialize
        @errorCount = 0
    end

    def errors
        return @errorCount
    end
    
    def flag(token : Token, errCode , parser : Parser)
        body = [convertErrCode(errCode),
                token.line.to_s,
                token.pos.to_s,
                token.text.to_s,
                parser.filename]
        msg  = Msg.new(MsgType::SINTAX_ERROR,body)
        parser.sendMsg(msg)
        @errorCount += 1
        if @errorCount > MAX_ERR
            abortProcess(parser)
        end
    end

    def abortProcess(parser : Parser)
        msg = Msg.new(MsgType::FATAL,["Too many errors"])
        parser.sendMsg(msg)
        exit 0
    end

    def abortProcess
        exit 0
    end

end