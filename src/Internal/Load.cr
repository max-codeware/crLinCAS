
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

module LinCAS::Internal

    REQUIRED = [] of String
    DirLib   = build_string(ENV["libDir"])
    Ext      = build_string(".lc")
    Sep      = build_string("/")

    ParserAbort = Parser::ParserAbort

    def self.check_required(path : String)
        return REQUIRED.includes? path 
    end

    def self.require_file(path :  LcVal,opt :  LcVal? = nil)
        path   = String.new(file_expand_path(path,opt))
        if !file_exist(path)
            lc_raise(LcLoadError,"No such file '#{path}'")
            return nil 
        else
            if !check_required(path)
                REQUIRED << path 
            else
                return nil 
            end
            parser = FFactory.makeParser(path)
            parser.singleErrOutput
            parser.handleMsg
            parser.noSummary
            begin 
                ast    = parser.parse
            rescue e : ParserAbort
            end
            
            if !(parser.errCount > 0) && ast
                iseq = Compile.compile(ast,Code::LEAVE)
                return iseq 
            else 
                lc_raise(LcSintaxError,parser.getErrMsg)
            end
        end
        return nil
    end

    def self.lc_require_file(path :  LcVal)
        str_check(path)
        iseq = require_file(path)
        if iseq 
            Exec.run(iseq)
            return lctrue
        end
        return lcfalse
    end

    require_file_ = LcProc.new do |args|
        next lc_require_file(lc_cast(args,T2)[1])
    end

    def self.lc_import_file(path :  LcVal)
        str_check(path)
        lc_str_concat(path,[Sep,lc_str_clone(path),Ext])
        iseq = require_file(path,DirLib)
        if iseq 
            Exec.run(iseq)
            return lctrue
        end
        return lcfalse
    end

    import_file = LcProc.new do |args|
        next lc_import_file(lc_cast(args,T2)[1])
    end

    def self.lc_require_relative(path :  LcVal)
        str_check(path)
        dir  = current_filedir
        dir  = build_string(dir)
        iseq = require_file(path,dir)
        if iseq
            Exec.run(iseq)
            return lctrue
        end 
        return lcfalse
    end

    require_relative = LcProc.new do |args|
        next lc_require_relative(lc_cast(args,T2)[1])
    end

    private def self.normalize_iseq(iseq : Bytecode)
        tmp = iseq
        2.times do
            break if iseq.nextc.nil?
            iseq = iseq.nextc.as(Bytecode)
        end
        iseq.lastc = tmp.lastc
        return iseq
    end

    private def self.get_last_is(is : Bytecode)
        if is.code.to_s.includes? "CALL"
            argc = is.argc 
            (argc + 2).times do |i|
                is = is.prev.as(Bytecode)
            end
            return is
        else
            lc_bug("(failed to replace bytecode)")
        end
    end

    def self.inline_iseq(iseq : Bytecode,is : Bytecode)
        tmp       = get_last_is(is)
        tmp.nextc = iseq
        iseq.prev = tmp
        follow    = is.nextc.as(Bytecode).nextc.as(Bytecode)
        last      = iseq.lastc.as(Bytecode)
        last.prev.as(Bytecode).nextc = follow 
        return tmp
    end

    def self.lc_replace(string :  LcVal)
        string = string2cr(string)
        if string
            parser = FFactory.makeParser(string,current_file,current_call_line)
            parser.singleErrOutput
            parser.handleMsg
            parser.noSummary
            begin 
                ast    = parser.parse
            rescue e : ParserAbort
            end

            if !(parser.errCount > 0) && ast
                iseq = Compile.compile(ast,Code::NOOP)
                iseq = normalize_iseq(iseq)
                Exec.vm_replace_iseq(iseq)
            else 
                lc_raise(LcSintaxError,parser.getErrMsg)
                return lcfalse
            end
            return lctrue
        end 
        return lcfalse
    end

    replace = LcProc.new do |args|
        next lc_replace(lc_cast(args,T2)[1])
    end


    internal.lc_module_add_internal(LKernel,"require",require_file_,                 1)
    internal.lc_module_add_internal(LKernel,"import",import_file,                    1)
    internal.lc_module_add_internal(LKernel,"require_relative",require_relative,     1)
    internal.lc_module_add_internal(LKernel,"replace",replace,                       1)

end