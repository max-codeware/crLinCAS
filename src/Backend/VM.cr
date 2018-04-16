
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

require "./VMcall_tracker"

class LinCAS::VM < LinCAS::MsgGenerator

    MAX_STACK_DEPTH = 2000

    alias Value   = Internal::Value
    alias ValueR  = Internal::ValueR
    alias LcError = Internal::LcError
    Null          = Internal::Null
    LcTrue        = Internal::LcTrue
    LcFalse       = Internal::LcFalse


    private struct ObjectWrapper
        def initialize(@object : Value)
        end
        getter object
    end

    macro wrap_object(object)
        ObjectWrapper.new({{object}})
    end

    macro unwrap_object(object)
        {{object}}.as(ObjectWrapper).object 
    end

    private class VMerror < Exception        
    end

    private class ErrorHandler
        @error : Value? = nil 
        @ex_h  = 0
        getter error 

        @[AlwaysInline]
        def exception_handler?
            return @ex_h > 0
        end

        @[AlwaysInline]
        def exception_handler=(value : Int32)
            @ex_h += value
        end

        @[AlwaysInline]
        def handled_error?
            return !!@error 
        end

        @[AlwaysInline]
        def handle_error(error : Value?)
            @error = error 
        end
    end

    class Scope < Hash(String,Value)

        def initialize
            super
        end

        @previous : Scope?   = nil
        @lcblock  : LcBlock? = nil 
        @ans      : Value    = Null

        property previous, lcblock, ans

        def set_var(name : String, object : Value)
            self[name] = object 
        end 

        def get_var(name : String)
            self[name]?
        end

    end

    enum FrameType
        CLASS_FRAME
        BLOCK_FRAME
        CALL_FRAME
        MAIN_FRAME
    end

    private class LcFrame
        @fp      = 0                          # frame pointer
        @pc      = uninitialized Bytecode     # program count
        @scp     = uninitialized Scope        # scope pointer
        @catch_t : CatchTable? = nil
        
        def initialize(@me : Value,@context : Structure,@argc : IntnumR,@type : FrameType)  
        end

        property fp,argc,pc,scp,me,context,catch_t,type

        @[AlwaysInline]
        def fetch 
            @pc.nextc
        end
    end

    private class FileInfo
        @line = 0.as(IntnumR)
        def initialize(@file : String)
        end
        property file,line
    end

    alias StackValue  = ObjectWrapper | Intnum | Scope

    ErrHandler  = ErrorHandler.new 
    CallTracker = VMcall_tracker.new

    W_true      = ObjectWrapper.new(LcTrue)
    W_false     = ObjectWrapper.new(LcFalse)
    W_null      = ObjectWrapper.new(Null)

    macro current_scope
        current_frame.scp
    end

    macro previous_scope_of(c_scope)
        {{c_scope}}.previous
    end

    macro internal 
        Internal 
    end

    macro call_internal(method,arg)
        {{method}}.call({{arg}}[0])
    end

    macro call_internal_1(method,arg)
        {{method}}.call({{arg}}[0],{{arg}}[1])
    end 

    macro call_internal_2(method,args)
        {{method}}.call({{args}}[0],{{args}}[1],{{args}}[2])
    end 

    macro call_internal_3(method,args)
        {{method}}.call({{args}}[0],{{args}}[1],{{args}}[2],{{args}}[3])
    end

    macro call_internal_n(method,args)
        {{method}}.call(args)
    end

    macro call_usr(method,argc)
        return nil unless vm_load_call_args({{method}}.args.as(Array(VoidArgument)),{{argc}})
        current_frame.pc = {{method}}.code.as(Bytecode)
    end

    macro discard_arguments(argc)
        @sp -= {{argc}}
    end

    macro convert(err)
        LinCAS.convert_error({{err}})
    end

    macro get_context
        @framev[@vm_fp - 1].context
    end

    macro push_frame(frame)
        if @vm_fp == @framev.size 
            @framev.push({{frame}})
        else
            @framev[@vm_fp] = {{frame}}
        end 
        @vm_fp += 1
    end

    macro current_frame
        @framev[@vm_fp - 1]
    end

    macro filename 
        @location[@lp - 1].file 
    end

    macro line 
        @location[@lp - 1].line 
    end

    macro set_line(line)
        @location[@lp - 1].line = {{line}}
    end 

    macro test(value)
        internal.test({{value}})
    end 

    @[AlwaysInline]
    private def class_of(obj : Value)
        if obj.is_a? Structure 
            #if internal.struct_type(obj.as(Structure),SType::CLASS)
            #    return obj.klass 
            #end
            return obj 
        else 
            return obj.klass 
        end
    end

    @[AlwaysInline]
    def internal_call(method,args,arity)
        case arity
            when 0
                return call_internal(method,args)
            when 1
                return call_internal_1(method,args)
            when 2
                return call_internal_2(method,args)
            when 3
                return call_internal_3(method,args)
            else
                return call_internal_n(method,args)
        end
    end


    def initialize
        @stack   = [] of StackValue
        @framev  = [] of LcFrame
        @sp      = 0                          # stack pointer
        @vm_fp   = 0                          # frame pointer
        @lp      = 0                          # location pointer

        @location   = [] of FileInfo
        @msgHandler = MsgHandler.new
        @internal   = false
        @quit       = false

        self.addListener(RuntimeListener.new)
    end

    @[AlwaysInline]
    def messageHandler
        @msgHandler
    end

    protected def vm_print_stack
        print '['
        (0...@sp).each do |i|
            element = @stack[i]
            if element.is_a? ObjectWrapper
                print "Object"
            elsif element.is_a? Bytecode
                print "pc"
            elsif element.is_a? Scope
                print "data"
            else
                print element
            end 
            print ',' if i < @sp - 1
        end
        puts ']'
    end

    @[AlwaysInline]
    protected def ensured_stack_space?(count)
        if @sp + count > MAX_STACK_DEPTH
            lc_raise(LcSystemStackError,"(Stack level too deep)")
            return false 
        end 
        return true
    end

    @[AlwaysInline]
    protected def push(object : StackValue)
        if ensured_stack_space? 1
            if @sp >= @stack.size
                @stack.push(object)
            else 
                @stack[@sp] = object 
            end  
            @sp += 1
        end
    end

    @[AlwaysInline]
    protected def pop 
        if @sp < 0
            raise VMerror.new("(VM ran in stack underflow)")
        end 
        @sp -= 1
        return @stack[@sp]
    end 

    @[AlwaysInline]
    protected def new_frame(self_ref : Value, context : Structure,argc : Int32,type : FrameType)
        if @vm_fp >= @framev.size
            return LcFrame.new(self_ref,context,argc,type)
        else
            fm         = @framev[@vm_fp]
            fm.me      = self_ref
            fm.context = context
            fm.argc    = argc
            fm.type    = type
            return fm 
        end
    end


    @[AlwaysInline]
    protected def vm_push_new_frame(self_ref : Value, context : Structure,argc = 0,type = FrameType::CALL_FRAME )
        fm           = new_frame(self_ref,context,argc,type)
        fm.fp        = @sp 
        scp          = Scope.new
        scp.previous = current_scope
        push(scp)
        fm.scp = scp
        push_frame(fm)
    end

    @[AlwaysInline]
    protected def vm_push_new_frame(self_ref : Value, context : Structure,argc, scpr : Scope,type = FrameType::BLOCK_FRAME)
        fm           = new_frame(self_ref,context,argc,type)
        fm.fp        = @sp 
        scp          = Scope.new
        scp.previous = scpr
        push(scp)
        fm.scp = scp
        push_frame(fm)
    end

    protected def push_shared_frame
        fm      = current_frame
        tmp     = new_frame(fm.me.as(Value),fm.context.as(Structure),fm.argc.as(Int32),fm.type)
        tmp.pc  = fm.pc 
        tmp.scp = fm.scp
        push_frame(tmp)
    end

    @[AlwaysInline]
    protected def vm_pop_frame
        @vm_fp -= 1
        fm      = @framev[@vm_fp]
        @sp     = fm.fp
        return fm.argc
    end

    @[AlwaysInline]
    protected def new_fileinfo(filename : String)
        loc = @location[@lp]?
        if loc 
            loc.file = filename
        else 
            loc = FileInfo.new(filename)
        end 
        return loc 
    end

    @[AlwaysInline]
    protected def vm_push_location(filename : String)
        loc = new_fileinfo(filename)
        if @lp == @location.size
            @location << loc
        else 
            @location[@lp] = loc
        end
        @lp += 1
    end

    macro vm_pop_location 
        @lp -= 1
    end

    @[AlwaysInline]
    def error?
        return ErrHandler.handled_error?
    end

    @[AlwaysInline]
    def fetch
        fm  = current_frame
        tmp = fm.fetch
        if tmp 
            fm.pc = tmp 
            return tmp
        else
            raise VMerror.new("VM failed to fetch bytecode")
        end 
    end

    @[AlwaysInline]
    def vm_set_ans(obj : Value)
        current_frame.scp.ans = obj 
    end

    @[AlwaysInline]
    def run(bytecode : Bytecode)
        obj    = internal.boot_main_object
        fm     = new_frame(obj,class_of(obj),0,FrameType::MAIN_FRAME)
        fm.pc  = bytecode
        scp    = Scope.new 
        fm.scp = scp
        push(scp)
        push_frame(fm)
        vm_run_bytecode
    end

    protected def vm_run_bytecode(handle_return = false)
        is = current_frame.pc
        loop do
            {% if flag?(:debug) %}
                puts "Executing code #{is.code}"
            {% end %}
            case is.code
                when Code::LINE
                    set_line(is.line)
                when Code::FILENAME
                    vm_push_location(is.text)
                when Code::HALT
                    exit 0
                when Code::QUIT
                    return Null 
                when Code::PUSHN
                    push(W_null)
                when Code::PUSHT
                    push(W_true)
                when Code::PUSHF
                    push(W_false)
                when Code::PUSHSELF
                    push(wrap_object(current_frame.me))
                when Code::PUSHINT
                    int = internal.num2int(is.value.as(Intnum))
                    push(wrap_object(int))
                when Code::PUSHFLO
                    flo = internal.num2float(is.value.as(Floatnum))
                    push(wrap_object(flo))
                when Code::PUSHSTR
                    str = internal.build_string(is.text)
                    push(wrap_object(str))
                when Code::POPOBJ
                    obj = unwrap_object(pop)
                    context = current_frame.scp 
                    context.ans = obj
                when Code::CALL
                    vm_call(is.text,is.argc)
                when Code::M_CALL
                    vm_m_call(is.text,is.argc)
                when Code::CALL_WITH_BLOCK
                    vm_call_with_block(is.text,is.argc,is.block.as(LcBlock))
                when Code::M_CALL_WITH_BLOCK
                    vm_m_call_with_block(is.text,is.argc,is.block.as(LcBlock))
                when Code::RETURN
                    vm_return
                    if handle_return
                        return unwrap_object(pop)
                    end
                when Code::NEXT
                    vm_next
                    if handle_return
                        return unwrap_object(pop)
                    end
                when Code::STOREL
                    vm_store_local(is.text,is.value.as(Intnum))
                when Code::STOREL_0
                    vm_store_local_0(is.text)
                when Code::STOREL_1
                    vm_store_local_1(is.text)
                when Code::STOREL_2
                    vm_store_local_2(is.text)
                when Code::LOADL
                    vm_load_n(is.text,is.value.as(Intnum))
                when Code::LOADL_0
                    vm_load_0(is.text)
                when Code::LOADL_1
                    vm_load_1(is.text)
                when Code::LOADL_2
                    vm_load_2(is.text)
                when Code::LOADV
                    vm_load_v(is.text)
                when Code::GETC
                    vm_get_c(is.text)
                when Code::LOADC
                    vm_load_c(is.text)
                when Code::PUT_CLASS
                    vm_put_class(is.text,is.jump.as(Bytecode))
                when Code::PUT_MODULE
                    vm_put_module(is.text,is.jump.as(Bytecode))
                when Code::LEAVE
                    vm_leave
                when Code::PUT_STATIC_METHOD
                    vm_put_static_method(is.text,is.method.as(LcMethod))
                when Code::PUT_INSTANCE_METHOD
                    vm_put_instance_method(is.text,is.method.as(LcMethod))
                when Code::LOADG
                    vm_load_g(is.text)
                when Code::STOREG
                    vm_store_g(is.text)
                when Code::ARY_NEW
                    vm_ary_new(is.value.as(Intnum))
                when Code::IRANGE_NEW
                    vm_range_new(true)
                when Code::ERANGE_NEW
                    vm_range_new(false)
                when Code::MX_NEW
                    vm_mx_new(is.value.as(Intnum),is.opt_v)
                when Code::NEW_OBJ
                    vm_new_obj
                when Code::OPT_CALL_INIT
                    vm_opt_call_init(is.argc,is.block)
                when Code::PUSHDUP
                    if @sp == 0
                        raise VMerror.new("(VM attempted to duplicate a missing object)")
                    else
                        obj = pop 
                        push(obj)
                        push(obj)
                    end 
                when Code::YIELD
                    vm_call_block(is.argc)
                when Code::JUMP
                    fm    = current_frame
                    fm.pc = is.jump.as(Bytecode)
                when Code::JUMPF
                    vm_jumpf(is.jump.as(Bytecode))
                when Code::JUMPT
                    vm_jumpt(is.jump.as(Bytecode))
                when Code::EQ_CMP
                    obj1 = unwrap_object(pop)
                    obj2 = unwrap_object(pop)
                    res = internal.lc_obj_match(obj2,obj1)
                    push(wrap_object(res))
                when Code::SET_C_T
                    current_frame.catch_t = is.catch_t.as(CatchTable)
                    push_shared_frame
                    ErrHandler.exception_handler = 1
                when Code::CLEAR_C_T
                    pc = current_frame.pc 
                    vm_pop_frame
                    fm         = current_frame
                    fm.pc      = pc 
                    fm.catch_t = nil
                    ErrHandler.exception_handler = -1
                when Code::STOREC
                    vm_store_c(is.text)
                when Code::PUSHANS 
                    ans = current_frame.scp.ans
                    push(wrap_object(ans))
                when Code::HASH_NEW
                    vm_hash_new(is.argc)
            end
            if ErrHandler.handled_error?
                vm_handle_error(ErrHandler.error.as(Value))
            end
            if @quit
                @quit = false
                return Null
            end
            is = fetch
        end
    end

# Call methods
begin

    @[AlwaysInline]
    protected def vm_arity_check(argc1 : Intnum, argc2 : Intnum)
        if !(argc1 >= argc2)
            lc_raise(LcArgumentError,convert(:few_args) % {argc1,argc2})
            return false 
        end 
        return true
    end

    @[AlwaysInline]
    protected def vm_get_args(argc)
        argv = [] of Value
        (argc + 1).downto 1 do |i|
            argv << unwrap_object(@stack[@sp - 1 - i])
        end
        return argv
    end

    @[AlwaysInline]
    protected def vm_handle_instance_method_exception(code : Intnum,owner : Structure)
        case code
            when 0
                lc_raise(LcNoMethodError,convert(:no_method) % owner.name)
            when 1
                lc_raise(LcNoMethodError,convert(:protected_method) % owner.name)
            when 2
                lc_raise(LcNoMethodError,convert(:private_method) % owner.name)
        end
    end

    @[AlwaysInline]
    protected def vm_handle_static_method_exception(owner : Structure)
        s_type = (owner.is_a? LcClass) ? "Class" : "Module"
        lc_raise(LcNoMethodError,convert(:no_s_method) % {owner.path.to_s,s_type})
    end

    @[AlwaysInline]
    protected def vm_fetch_instance_method(obj_class : Structure,name : String)
        method = internal.seek_method(obj_class,name)
        if !(method.is_a? LcMethod)
            vm_handle_instance_method_exception(method.as(Intnum),obj_class)
            return nil 
        end
        return method.as(LcMethod)
    end

    @[AlwaysInline]
    protected def vm_fetch_instance_method_with_context(obj_class : Structure,name : String)
        context = get_context
        method  = internal.seek_method(context,name,true)
        if !(method.is_a? LcMethod)
            vm_handle_instance_method_exception(method.as(Intnum),obj_class)
            return nil 
        end
        return method.as(LcMethod)
    end

    @[AlwaysInline]
    protected def vm_fetch_static_method(receiver : Structure,name : String)
        method = internal.seek_static_method(receiver,name)
        if !(method.is_a? LcMethod)
            vm_handle_static_method_exception(receiver)
            return nil
        end
        return method.as(LcMethod)
    end

    @[AlwaysInline]
    protected def fetch_call_method(receiver : Value, name : String)
        if receiver.is_a? Structure
            return vm_fetch_static_method(receiver,name)
        else
            return vm_fetch_instance_method_with_context(class_of(receiver),name)
        end
    end

    @[AlwaysInline]
    protected def fetch_method(receiver : Value, name : String)
        if receiver.is_a? Structure
            return vm_fetch_static_method(receiver,name)
        else
            return vm_fetch_instance_method(class_of(receiver),name)
        end
    end

    @[AlwaysInline]
    protected def vm_get_receiver(argc)
        return unwrap_object(@stack[@sp - argc - 1])
    end

    protected def vm_call(name : String, argc : Intnum)
        CallTracker.push_track(filename,line,name)
        selfr  = vm_get_receiver(argc)
        method = fetch_call_method(selfr,name)
        if method
            vm_push_new_frame(selfr,method.owner.as(Structure),argc)
            return nil unless vm_arity_check(argc,method.arity)
            if method.internal
                argv  = vm_get_args(argc)
                value = internal_call(method.code.as(LcProc),argv,method.arity)
                push(wrap_object(value.as(Value)))
                vm_return_internal
            else
                call_usr(method,argc)
            end
        end
    end

    protected def vm_m_call(name : String, argc : Intnum)
        CallTracker.push_track(filename,line,name)
        receiver  = vm_get_receiver(argc)
        method    = fetch_method(receiver,name)
        if method
            vm_push_new_frame(receiver,method.owner.as(Structure),argc)
            return nil unless vm_arity_check(argc,method.arity)
            if method.internal
                @internal = true
                argv  = vm_get_args(argc)
                value = internal_call(method.code.as(LcProc),argv,method.arity)
                push(wrap_object(value.as(Value)))
                vm_return_internal
            else
                @internal = false
                call_usr(method,argc)
            end
        end
    end

    protected def vm_set_block(block : LcBlock)
        fm          = current_frame
        scp         = fm.scp
        block.scp   = scp 
        block.me    = fm.me
        scp.lcblock = block 
    end

    protected def vm_call_with_block(name : String,argc : Intnum, block : LcBlock)
        vm_set_block(block)
        vm_call(name,argc)
    end

    protected def vm_m_call_with_block(name : String,argc : Intnum, block : LcBlock)
        vm_set_block(block)
        vm_m_call(name,argc)
    end

    @[AlwaysInline]
    protected def vm_return_internal
        value = pop 
        argc  = vm_pop_frame
        discard_arguments(argc + 1)
        CallTracker.pop_track
        push(value)
    end

    protected def vm_return
        value = pop
        argc  = vm_pop_frame
        discard_arguments(argc + 1)
        CallTracker.pop_track
        vm_pop_location
        push(value)
        current_frame.scp.lcblock = nil
    end

end
    
    private def get_arg(n)
        argc = current_frame.argc
        if argc > n && argc > 0
            return @stack[@sp - argc - 1 + n]
        else
            return nil
        end
    end

    protected def vm_load_call_args(argv : Array(VoidArgument),argc : Intnum)
        count = 0
        argv.each do |arg|
            value = get_arg(count)
            name  = arg.name
            if !arg.opt && value
                store_local(name,unwrap_object(value))
            elsif !arg.opt
                lc_raise(LcArgumentError,convert(:few_args) % {count,argc})
                return nil
            end
            if value
                store_local(name,unwrap_object(value))
            else
                pc  = current_frame.pc 
                current_frame.pc = arg.optcode.as(Bytecode)
                vm_run_bytecode
                current_frame.pc = pc 
            end
            count += 1
        end
        return true
    end

    protected def store_local(name : String,value : Value)
        scp = current_scope
        scp.set_var(name,value)
    end

# Store 
begin

    protected def vm_store_local_0(name : String)
        value = pop
        scp   = current_scope
        scp.set_var(name,unwrap_object(value))
        push(value)
    end

    protected def vm_store_local_1(name : String)
        value = pop
        scp   = current_scope.previous.as(Scope)
        scp.set_var(name,unwrap_object(value))
        push(value)
    end

    protected def vm_store_local_2(name : String)
        value = pop
        scp   = current_scope.previous.as(Scope).previous.as(Scope)
        scp.set_var(name,unwrap_object(value))
        push(value)
    end

    protected def vm_store_local(name : String, depth : Intnum)
        value = pop 
        scp   = current_scope
        depth.times do |i|
            scp = scp.previous.as(Scope)
        end
        scp.set_var(name,unwrap_object(value))
        push(value)
    end

    protected def vm_store_g(name : String)
        value    = unwrap_object(pop)
        receiver = unwrap_object(pop)
        receiver.data.addVar(name,value)
        push(wrap_object(value))
    end

    protected def vm_store_c(name : String)
        value = unwrap_object(pop)
        obj   = unwrap_object(pop)
        klass = class_of(obj)
        const = internal.lc_seek_const(klass,name)
        if const 
            lc_raise_1(LcNameError,"Constant already defined")
        else
            internal.lc_define_const(klass,name,value)
        end
        push(wrap_object(obj))
    end
end

# load
begin 

    protected def vm_load_v(name : String)
        scp   = current_scope
        value = scp.get_var(name)
        if value 
            push(wrap_object(value))
        else 
            klass = class_of(current_frame.me)
            const = internal.lc_seek_const(klass,name)
            if const
                push(wrap_object(const.as(Value)))
            else
                lc_raise_1(LcNameError,convert(:undefined_id) % {name,klass.path.to_s})
                push(W_null)
            end
        end 
    end
    
    protected def vm_load_n(name : String, depth : Intnum)
        scp = current_scope
        depth.times do |i|
            scp = scp.previous.as(Scope)
        end
        value = scp.get_var(name)
        if value 
            push(wrap_object(value))
        else 
            lc_raise_1(LcNameError,convert(:undef_var) % name)
            push(W_null)
        end
    end

    protected def vm_load_0(name : String)
        scp   = current_scope
        value = scp.get_var(name)
        if value 
            push(wrap_object(value))
        else 
            lc_raise_1(LcNameError,convert(:undef_var) % name)
            push(W_null)
        end
    end

    protected def vm_load_1(name : String)
        scp   = current_scope.previous.as(Scope)
        value = scp.get_var(name)
        if value 
            push(wrap_object(value))
        else 
            lc_raise_1(LcNameError,convert(:undef_var) % name)
            push(W_null)
        end
    end

    protected def vm_load_2(name : String)
        scp   = current_scope.previous.as(Scope).previous.as(Scope)
        value = scp.get_var(name)
        if value 
            push(wrap_object(value))
        else 
            lc_raise_1(LcNameError,convert(:undef_var) % name)
            push(W_null)
        end
    end

    protected def vm_load_c(name : String)
        selfr = unwrap_object(pop)
        if !(selfr.is_a? Structure)
            klass = class_of(selfr)
        else
            klass = selfr.as(Structure)
        end
        const = internal.lc_seek_const(klass,name)
        if const
            push(wrap_object(const))
        else
            path = klass.path
            lc_raise_1(LcNameError,convert(:undef_const_2) % {name,path.empty? ? klass.name : path.to_s})
            push(W_null)
        end
    end

    protected def vm_load_g(name : String)
        obj   = unwrap_object(pop)
        value = obj.data.getVar(name)
        if value
            push(wrap_object(value))
        else 
            push(W_null)
        end
    end

end

    protected def vm_get_c(name : String)
        prev = unwrap_object(pop)
        if !(prev.is_a? Structure)
            lc_raise_1(LcNameError,convert(:not_a_struct) % name)
            push(W_null)
            return nil
        end
        prev = prev.as(Structure)
        const = internal.lc_seek_const(prev,name)
        if const 
            push(wrap_object(const.as(Value)))
        else
            lc_raise_1(LcNameError,convert(:undef_const_2) % {name,prev.path.to_s})
            push(W_null)
        end
    end

    protected def vm_put_class(name : String,bytecode : Bytecode)
       parent  = unwrap_object(pop) 
       obj     = unwrap_object(pop)
       p_scope = class_of(obj)
       klass   = vm_create_class(name,parent,p_scope)
       if klass
           vm_push_new_frame(klass,klass,0,FrameType::CLASS_FRAME)
           current_frame.pc = bytecode
           CallTracker.push_track(filename,line,"<class:%s>" % name)
       end
    end

    protected def vm_create_class(name : String,parent : Value,scope : Structure)
        p_def = internal.lc_seek_const(scope,name)
        if p_def.is_a? LcClass
            if p_def.frozen
                lc_raise(LcFrozenError,convert(:frozen_class))
                return nil 
            end 
            return p_def
        elsif p_def.nil?
            path  = scope.path
            klass = internal.lc_build_class(name,path.addName(name))
            return nil unless vm_set_parent(klass,parent)
            klass.symTab.parent = scope.symTab 
            scope.symTab.addEntry(name,klass)
            return klass
        else 
            lc_raise_1(LcTypeError,convert(:not_a_class) % name)
            return nil
        end
    end

    protected def vm_set_parent(klass : LcClass,parent : Value)
        if !(parent.is_a? Structure) && parent != Null
            lc_raise_1(LcTypeError,convert(:no_parent) % internal.lc_typeof(parent))
            push(wrap_object(klass))
            return nil
        end 
        if klass.parent && parent != Null 
            lc_raise_1(LcTypeError,convert(:superclass_err) % klass.name)
            return nil
        elsif !(klass.parent) && parent == Null 
            internal.lc_set_parent_class(klass,Internal::Obj)
            return true
        end
        return true if parent == Null
        internal.lc_set_parent_class(klass,parent.as(LcClass))
        return true
    end

    protected def vm_put_module(name : String, bytecode : Bytecode)
        obj     = unwrap_object(pop)
        p_scope = class_of(obj)
        mod     = vm_create_module(name,p_scope)
        if mod 
           vm_push_new_frame(mod,mod,0,FrameType::CLASS_FRAME)
           current_frame.pc = bytecode
           CallTracker.push_track(filename,line,"<module:%s>" % name)
        end
    end

    protected def vm_create_module(name : String, scope : Structure)
        p_def = internal.lc_seek_const(scope,name)
        if p_def.is_a? LcModule
            if p_def.frozen
                lc_raise(LcFrozenError,convert(:frozen_module))
                return nil 
            end 
            return p_def
        elsif p_def.nil?
            path  = scope.path
            mod   = internal.lc_build_module(name,path.addName(name))
            mod.symTab.parent = scope.symTab 
            scope.symTab.addEntry(name,mod)
            return mod
        else 
            lc_raise_1(LcTypeError,convert(:not_a_module) % name)
            return nil
        end
    end

    protected def vm_leave
        fm = current_frame
        vm_pop_frame
        frame_t = fm.type
        if frame_t == FrameType::CLASS_FRAME
            me = fm.me 
            CallTracker.pop_track
            vm_set_ans(me)
        elsif frame_t == FrameType::MAIN_FRAME
            vm_set_ans(fm.scp.ans)
            vm_pop_location
            @quit = true
        else 
            raise VMerror.new("VM was asked to leave a wrong frame (#{frame_t})")
        end
    end

    protected def vm_next 
        value = pop
        argc  = vm_pop_frame
        discard_arguments(argc)
        CallTracker.pop_track
        vm_pop_location
        push(value)
    end

    protected def vm_get_block
        fm    = current_frame
        if fm.type == FrameType::BLOCK_FRAME
            scp = previous_scope_of(fm.scp)
            if !scp 
                return nil
            end
            scp = previous_scope_of(scp)
            if scp
                return scp.lcblock
            end
        else
            scp   = fm.scp
            p_scp = scp.previous
            if p_scp
                return p_scp.lcblock
            end 
        end
        return nil
    end

    protected def vm_call_block(argc : Intnum)
        block = vm_get_block
        fm    = current_frame
        if block 
            CallTracker.push_track(filename,line,"<block>")
            vm_push_new_frame(fm.me,fm.context,argc,block.scp.as(Scope))
            fm = current_frame
            fm.pc = block.body
            vm_load_call_args(block.args,argc)
        else 
            lc_raise(LcArgumentError,convert(:no_block) % "(yield)")
        end
    end

    protected def vm_put_static_method(name : String,method : LcMethod)
        klass        = class_of(unwrap_object(pop))
        method.owner = klass
        klass.statics.addEntry(name,method)
    end

    protected def vm_put_instance_method(name : String,method : LcMethod)
        object       = pop
        klass        = class_of(unwrap_object(object))
        method.owner = klass
        klass.methods.addEntry(name,method)
        push(object)
    end

    protected def vm_ary_new(size : Intnum)
        ary = internal.new_ary 
        i   = 0
        while i < size 
            obj = unwrap_object(pop)
            internal.lc_ary_push(ary,obj)
            i += 1
        end 
        push(wrap_object(ary))
    end

    protected def vm_range_new(inclusive)
        right = unwrap_object(pop)
        left  = unwrap_object(pop)
        range = internal.build_range(left,right,inclusive)
        push(wrap_object(range))
    end

    protected def vm_mx_new(rws : Intnum, cls : Intnum)
        i = 0
        j = 0
        mx = internal.build_matrix(rws,cls)
        while i < rws 
            while j < cls 
                value = unwrap_object(pop)
                internal.lc_set_matrix_index(mx,i,j,value)
                j += 1
            end 
            i += 1 
            j  = 0
        end
        push(wrap_object(mx))
    end

    protected def vm_hash_new(size : IntnumR)
        hash = internal.build_hash
        size.times do
            value = unwrap_object(pop)
            key   = unwrap_object(pop)
            internal.lc_hash_set_index(hash,key,value)
        end
        push(wrap_object(hash))
    end

    protected def vm_new_obj
        CallTracker.push_track(filename,line,"new")
        klass = unwrap_object(pop)
        if !(klass.is_a? LcClass)
            lc_raise(LcTypeError,"Argument of new must be a class (#{internal.lc_typeof(klass)} given)")
            return nil 
        end
        obj   = internal.lc_new_object(klass)
        push(wrap_object(obj))
        CallTracker.pop_track
    end

    protected def vm_opt_call_init(argc : Intnum,block : LcBlock? = nil)
        init = "init"
        obj  = @stack[@sp - argc - 1].as(ObjectWrapper)
        obj  = unwrap_object(obj)
        if internal.lc_obj_responds_to?(obj,init)
            if block
                vm_m_call_with_block(init,argc,block)
            else
                vm_m_call(init,argc)
            end
        end
    end

    protected def vm_jumpf(code : Bytecode)
        obj = unwrap_object(pop)
        if !test(obj)
            fm    = current_frame
            fm.pc = code 
        end
    end

    protected def vm_jumpt(code : Bytecode)
        obj = unwrap_object(pop)
        if test(obj)
            fm    = current_frame
            fm.pc = code 
        end
    end


    protected def lc_raise_1(code,msg)
        backtrace = String.build do |io|
            io << "line: " << line    << '\n'
            io << "in: "   << filename << '\n'
            io << CallTracker.get_backtrace
        end
        error_body = String.build do |str|
            str << '\n'
            str << code
            str << ": "
            str << msg
        end
        error = internal.build_error(code,msg,backtrace) 
        ErrHandler.handle_error(error)
    end


    def lc_raise(code,msg)
        backtrace = CallTracker.get_backtrace
        error_body = String.build do |str|
            str << '\n'
            str << code
            str << ": "
            str << msg
        end
        error = internal.build_error(code,msg,backtrace) 
        ErrHandler.handle_error(error)
    end

    def lc_raise(error : Value)
        error = error.as(LcError)
        error.backtrace = CallTracker.get_backtrace
        ErrHandler.handle_error(error)
    end 

    def lc_yield(*args : Value)
        vm_push_args(args)
        if block_given?
            vm_call_block(args.size)
            return vm_run_bytecode(true).as(Value)
        else 
            lc_raise(LcArgumentError,convert(:no_block))
        end
    end

    def lc_call_fun(receiver : Value, method : String, *args)
        push(wrap_object(receiver))
        vm_push_args(args)
        vm_m_call(method,args.size)
        if @internal
            return unwrap_object(pop)
        else
            return vm_run_bytecode(true)
        end
    end

    protected def vm_push_args(args)
        args.each do |arg|
            push(wrap_object(arg))
        end 
    end

    @[AlwaysInline]
    def block_given?
        !!vm_get_block
    end

    @[AlwaysInline]
    protected def get_catch_t
        catch_t = current_frame.catch_t
        while !catch_t && @vm_fp > 0
            vm_pop_frame
            catch_t = current_frame.catch_t 
        end 
        if !catch_t
            raise VMerror.new("Catch table not found")
        end 
        return catch_t
    end

    protected def vm_handle_error(error : Value)
        if ErrHandler.exception_handler?
            catch_t = get_catch_t
            name = catch_t.var_name
            iseq = catch_t.code 
            if name 
                store_local(name,ErrHandler.error.as(LcError))
            end 
            ErrHandler.handle_error(nil)
            ErrHandler.exception_handler = -1
            current_frame.pc = iseq
        else
            error = ErrHandler.error.as(LcError)
            msg   = String.build do |io|
                io << error.body 
                io << '\n' << error.backtrace
            end
            sendMsg(Msg.new(MsgType::RUNTIME_ERROR,[msg]))
        end
    end

    def print_end_backtrace
        backtrace = CallTracker.get_backtrace
        sendMsg(Msg.new(MsgType::BACKTRACE,[backtrace]))
    end

    def get_current_filedir
        return File.dirname(filename)
    end

end

module LinCAS
    Exec = VM.new
end