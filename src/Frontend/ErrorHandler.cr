
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

class LinCAS::ErrorHandler

    MAX_ERR = 10

    def initialize
        @errorCount   = 0
        @singleOutput = false
    end

    def errors
        return @errorCount
    end

    def singleOutput
        @singleOutput = true
    end
    
    def flag(token : Token, errCode , parser : Parser)
        return if @singleOutput
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
        exit 1
    end

    def abortProcess
        exit 1
    end

end
