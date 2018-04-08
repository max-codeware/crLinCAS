
# Copyright (c) 2017-2018 Massimiliano Dal Mas
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

class LinCAS::Eval < LinCAS::MsgGenerator

    alias LcKernel = Internal::LcKernel
    
    macro null
        Internal::Null
    end

    macro convert(err)
        LinCAS.convert_error({{err}})
    end

    macro internal
        Internal
    end

    macro find(name)
        Id_Tab.lookUp({{name}})
    end

    macro find_local(name)
        Id_Tab.lookUpLocal({{name}})
    end

    macro reopen(klass)
        Id_Tab.enterScope({{klass}}.as(Structure))
    end

    macro exit_scope
        Id_Tab.exitScope
    end

    macro current_scope
        Id_Tab.getCurrent
    end

    macro unpack_name(node)
        {{node}}.getAttr(NKey::ID).as(String)
    end

    macro send_msg(msg)
        sendMsg(Msg.new(MsgType::RUNTIME_ERROR,[{{msg}}]))
    end

    macro check_arity(method,args)
        {{method}}.arity <= args.size
    end

    macro push_frame(filename,line,name,object)
        @callstack.pushFrame({{filename}}.as(String),{{line}}.as(Intnum),{{name}}.as(String),{{object}})
    end
    
    macro push_frame(filename,line,name)
        @callstack.pushFrame({{filename}}.as(String),{{line}}.as(Intnum),{{name}}.as(String))
    end

    macro push_duplicated_frame
        @callstack.push_duplicated_frame
    end

    macro push_cloned_frame
        @callstack.push_cloned_frame
    end

    macro pop_frame
        @callstack.popFrame 
    end

    macro set_object(obj)
        @callstack.object = {{obj}}
    end

    macro current_object
        @callstack.object.as(Internal::Value)
    end 

    macro set_local(name,value)
        @callstack.setVar({{name}}.as(String),{{value}}.as(Internal::Value))
    end 

    macro delete_local(name)
        @callstack.deleteVar({{name}}.as(String))
    end

    macro bind_method(scope,name,method)
        {{scope}}.methods.addEntry({{name}},{{method}})
    end

    macro bind_static_method(scope,name,method)
        {{scope}}.statics.addEntry({{name}},{{method}})
    end 

    macro set_block(block)
        @callstack.set_block({{block}})
    end 

    macro get_block
        @callstack.get_block
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

    macro set_last_method(m)
        @callstack.method = {{m}} 
    end 

    macro get_last_method
        @callstack.method
    end

    @[AlwaysInline]
    def internal_call(method,args,arity)
        args = args.to_a
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


    @error : Internal::Value?

    def initialize
        @callstack  = CallStack.new
        @msgHandler = MsgHandler.new
        @try        = 0
        @error      = nil
        self.addListener(RuntimeListener.new)
    end

    def messageHandler
        @msgHandler
    end

    def error?
        return @error ? true : false 
    end

    def eval(program : Node?)
        if program
            obj = internal.boot_main_object
            push_frame(find_file(program.as(Node)),0,"Main",obj)
            method       = MethodEntry.new("Main",VoidVisib::PUBLIC)
            method.owner = obj.as(Internal::ValueR).klass
            set_last_method(method)
            eval_stmt(program) 
            pop_frame
        end
        puts
    end

    protected def eval_stmt(node : Node)
        case node.type
            when NodeType::PROGRAM
                return eval_program(node)
            when NodeType::READS
                return eval_reads(node)
            when NodeType::PRINT, NodeType::PRINTL
                return eval_print(node)
            when NodeType::CLASS 
                eval_class(node)
            when NodeType::MODULE 
                eval_module(node)
            when NodeType::VOID
                eval_void(node)
            when NodeType::CALL, NodeType::METHOD_CALL
                return eval_exp(node)
            when NodeType::RETURN
                return eval_return(node)
             when NodeType::WHILE
                return eval_while(node)
            when NodeType::UNTIL
                return eval_until(node)
            when NodeType::IF
                return eval_if(node)
            when NodeType::SELECT
                return eval_select(node)
            when NodeType::INCLUDE
                eval_include(node)
            when NodeType::ASSIGN
                eval_assign(node)
            when NodeType::APPEND
                eval_append(node)
            when NodeType::CONST
                eval_const(node)
            when NodeType::NEW
                eval_new(node)
            when NodeType::TRY 
                return eval_try(node)
            when NodeType::BODY 
                return eval_body(node)
            when NodeType::YIELD
                return eval_yield(node)
            when NodeType::RAISE
                eval_raise(node)
        end
        return null
    end

    protected def eval_program(node : Node) : Nil
        branches = node.getBranches
        branches.each do |branch|
            eval_stmt(branch)
        end
    end

    protected def eval_reads(node)
        return LcKernel.in
    end

    protected def eval_print(node)
        args = node.getBranches
        case node.type
            when NodeType::PRINT
                if args.size > 0
                    (0...args.size).each do |i|
                        val = eval_exp(args[i])
                        break if @error
                        LcKernel.out(val)
                    end
                else
                    print ""
                end
            when NodeType::PRINTL
                if args.size > 0
                    (0...args.size).each do |i|
                        val = eval_exp(args[i])
                        break if @error
                        LcKernel.outl(val)
                    end
                else 
                    LibC.printf("\n","")
                end
        end
    end

    protected def eval_exp(node : Node)
        case node.type
            when NodeType::STRING
                string = node.getAttr(NKey::VALUE).as(String)
                return internal.build_string(string)
            when NodeType::TRUE
                return Internal::LcTrue
            when NodeType::FALSE
                return Internal::LcFalse
            when NodeType::INT
                return internal.num2int(node.getAttr(NKey::VALUE).as(Intnum))
            when NodeType::FLOAT
                return internal.num2float(node.getAttr(NKey::VALUE).as(Floatnum))
            when NodeType::GLOBAL_ID
                return eval_global_id(node)
            when NodeType::LOCAL_ID
                return eval_local_id(node)
            when NodeType::NAMESPACE
                return eval_namespace(node)
            when NodeType::ARRAY
                return eval_array(node)
            when NodeType::IRANGE, NodeType::ERANGE
                return eval_range(node)
            when NodeType::MATRIX
                return eval_matrix(node)
#            when NodeType::SYMBOLIC

            when NodeType::CALL
                return eval_call(node)
            when NodeType::METHOD_CALL
                return eval_method_call(node)
            when NodeType::NEW
                return eval_new(node)
            when NodeType::READS
                return eval_reads(node)
            when NodeType::NULL
                return null
            when NodeType::YIELD
                return eval_yield(node)
        else
            return eval_bin_op(node)
        end
        return null
    end

    macro calculate_binary(node)
        branches = {{node}}.getBranches
        left     = branches[0]
        right    = branches[1]
        l_val    = eval_exp(left).as(Internal::Value)
        r_val    = eval_exp(right).as(Internal::Value)
    end

    protected def eval_bin_op(node : Node)
        l_val = uninitialized Internal::Value 
        r_val = uninitialized Internal::Value
        case node.type
            when NodeType::SUM 
                calculate_binary(node)
                return call_fun(node,l_val,"+",r_val)
            when NodeType::SUB 
                calculate_binary(node)
                return call_fun(node,l_val,"-",r_val)
            when NodeType::MUL 
                calculate_binary(node)
                return call_fun(node,l_val,"*",r_val)
            when NodeType::FDIV  
                calculate_binary(node)
                return call_fun(node,l_val,"/",r_val)
            when NodeType::IDIV 
                calculate_binary(node)
                return call_fun(node,l_val,"\\",r_val)
            when NodeType::POWER 
                calculate_binary(node)
                return call_fun(node,l_val,"^",r_val)
            when NodeType::MOD
                calculate_binary(node)
                return call_fun(node,l_val,"%",r_val)
            when NodeType::AND
                calculate_binary(node)
                return call_fun(node,l_val,"&&",r_val)
            when NodeType::OR  
                calculate_binary(node)
                return call_fun(node,l_val,"||",r_val)
            when NodeType::GR  
                calculate_binary(node)
                return call_fun(node,l_val,">",r_val)
            when NodeType::GE  
                calculate_binary(node)
                return call_fun(node,l_val,">=",r_val)
            when NodeType::SM 
                calculate_binary(node)
                return call_fun(node,l_val,"<",r_val)
            when NodeType::SE 
                calculate_binary(node)
                return call_fun(node,l_val,"<=",r_val)
            when NodeType::EQ 
                calculate_binary(node)
                return call_fun(node,l_val,"==",r_val)
            when NodeType::NE 
                calculate_binary(node)
                if internal.lc_obj_responds_to? l_val,"!="
                    return call_fun(node,l_val,"!=",r_val)
                elsif internal.lc_obj_responds_to? l_val,"=="
                    bool = call_fun(node,l_val,"==",r_val)
                    return internal.lc_bool_invert(bool)
                else
                    lc_raise(LcNoMethodError,"Undefined method '!=' for #{internal.lc_typeof(l_val)}")
                    return null
                end
            when NodeType::NOT
                arg     = node.getBranches[0]
                arg_val = eval_exp(arg).as(Internal::Value)
                return call_fun(node,arg_val,"!")
            when NodeType::INVERT
                arg     = node.getBranches[0]
                arg_val = eval_exp(arg).as(Internal::Value)
                return call_fun(node,arg_val,"invert")
        else
            lc_raise(LcInternalError,convert(:wrong_node_reached),node)
            return null
        end
        # Should never get here
        null
    end

    protected def eval_global_id(node : Node)
        obj  = current_object
        name = unpack_name(node)
        val  = obj.data.getVar(name)
        if val
            return val 
        else 
            obj.data.addVar(name,null)
            return null 
        end
    end

    protected def eval_local_id(node : Node)
        name = unpack_name(node) 
        val = @callstack.getVar(name)   
        if val 
            return val 
        else
            obj = current_object
            if obj.is_a? Structure
                obj = obj.as(Structure)
            else 
                obj = obj.as(Internal::ValueR).klass
            end
            val = internal.lc_seek_const(obj,name) 
            return val if val 
            lc_raise(LcNameError,convert(:undefined_id) % name,node)
            return null
        end
    end

    private def find_method(owner,name,protctd)
        method = internal.seek_method(owner,name,protctd)
            case method
                when 0
                    lc_raise(LcNoMethodError,convert(:no_method) % owner.name) 
                    return nil
                when 1
                    lc_raise(LcNoMethodError,convert(:protected_method) % owner.name)
                    return nil
                when 2
                    lc_raise(LcNoMethodError,convert(:private_method) % owner.name)
                    return nil
            end
        return method
    end

    private def seek_method(receiver,name,protctd = false)
        receiver = eval_stmt(receiver).as(Internal::Value) if receiver.is_a? Node
        if receiver.is_a? Structure
            method = internal.seek_static_method(receiver,name)
            unless method.is_a? MethodEntry
                s_type = (receiver.is_a? ClassEntry) ? "Class" : "Module"
                lc_raise(LcNoMethodError,convert(:no_s_method) % {receiver.path.to_s,s_type})
                return null
            end
        else 
            method = find_method(class_of(receiver),name,protctd)  
        end
        return method if method.is_a? MethodEntry
        return nil
    end

    protected def seek_method_2(receiver,name,protctd,static)
        if static 
            return seek_method(receiver,name)
        else 
            method = find_method(receiver,name,protctd)
        end 
        return method
    end 

    protected def eval_call(node : Node)
        branches = node.getBranches
        name     = unpack_name(branches[0])
        args     = branches[1]
        argv     = eval_args(args)
        current_obj = current_object
        l_method    = get_last_method.as(MethodEntry)
        owner       = l_method.owner.as(Structure)
        push_frame(find_file(node),find_line(node),name,current_obj)
        static = (current_obj.is_a? Structure)
        method = seek_method_2(owner,name,true,static)
        if method
            execute_fun(current_obj,method,argv)
        else 
            pop_frame 
        end
    end

    protected def eval_method_call(node : Node)
        receiver = node.getAttr(NKey::RECEIVER)
        branches = node.getBranches
        name     = branches[0]
        args     = branches[1]
        voidName = unpack_name(name).as(String)
        vReceiver = eval_exp(receiver.as(Node)).as(Internal::Value)
        argv    = eval_args(args)
        push_frame(find_file(node),find_line(node),voidName,vReceiver)
        method = seek_method(vReceiver,voidName)
        if method
            return execute_fun(vReceiver,method,argv)
        else 
            pop_frame
        end 
        return null
    end

    protected def call_fun(node : Node,receiver,name : String, *args)
        push_frame(find_file(node),find_line(node),name,receiver)
        method = seek_method(receiver,name)
        if method
            return execute_fun(receiver,method,args)
        else 
            pop_frame
        end 
        return null
    end

    protected def call_fun(receiver,name : String,argv)
        method = seek_method(receiver,name)
        if method 
            return execute_fun(receiver,method,argv)
        end 
        return null
    end

    def lc_call_fun(receiver,name : String, *args)
        method = seek_method(receiver,name)
        push_duplicated_frame
        if method
            return execute_fun(receiver,method,args)
        else 
            pop_frame
        end 
        return null 
    end

    protected def execute_fun(receiver,method,args)
        method = method.as(MethodEntry)
        name = @callstack.last.callname
        set_last_method(method)
        unless check_arity(method,args)
            lc_raise(LcArgumentError,convert(:few_args) % {args.size,method.arity})
            pop_frame
            return null
        end
        if method.internal 
            code   = method.code.as(LcProc) 
            if args.is_a? Array
                f_args = ([receiver.as(Internal::Value)] + args).as(An)
            else 
                f_args = ({receiver.as(Internal::Value)} + args) 
            end 
            output = internal_call(code,f_args,method.arity)
            pop_frame
            return output
        else
            m_arg = method.args 
            body  = method.code
            load_call_args(m_arg.as(Node).getBranches,args)
            if @error
                pop_frame
                return null
            end
            output = eval_body(body.as(Node))
            if output && output.is_a? StackFrame
                return output.return_val
            else
                pop_frame
                return null
            end
        end
        return null
    end

    protected def eval_args(args : Node)
        branches = args.getBranches
        block    = args.getAttr(NKey::BLOCK)
        if block 
            set_block(block.as(Node))
        end
        return Tuple.new if branches.size == 0
        argv = [eval_exp(branches[0]).as(Internal::Value)]
        (1...branches.size).each do |i|
            tmp = branches[i]
            argv += [eval_exp(tmp).as(Internal::Value)]
        end
        return argv 
    end

    protected def load_call_args(m_args,args)
        m_args.each_with_index do |arg,i|
            val = args[i]?
            if val
                if arg.as(Node).type == NodeType::ASSIGN
                    name = unpack_name(arg.getBranches[0])
                else
                    name  = unpack_name(arg)
                end
                set_local(name,val)
            else 
                if arg.as(Node).type == NodeType::ASSIGN
                    eval_assign(arg)
                else
                    lc_raise(LcArgumentError,convert(:few_args) % {args.size,m_args.size})
                end
            end 
        end
    end

    protected def eval_class(node : Node)
        namespace   = node.getAttr(NKey::NAME).as(Node)
        parent      = node.getAttr(NKey::PARENT)
        body        = node.getBranches[0]
        name        = namespace.as(Node).getBranches
        if name.size == 1
            name  = unpack_name(name[0])
            push_frame(find_file(node),find_line(node),name)
            klass = find(name)
            klass = define_class(klass,name)
        else
            scope = eval_namespace(namespace.as(Node),false)
            reopen(scope)
            name  = unpack_name(name.last)
            push_frame(find_file(node),find_line(node),name)
            klass = find_local(name)
            klass = define_class(klass,name)
        end
        if klass.nil?
            pop_frame
            return nil 
        end
        set_object(klass.as(Internal::Value))
        if klass.as(ClassEntry).parent.nil? && parent
            parent = eval_namespace(parent.as(Node))
            lc_raise(
                LcTypeError,convert(:not_a_class) % stringify_namespace(namespace),node
            ) unless parent.is_a? ClassEntry
            internal.lc_set_parent_class(klass.as(ClassEntry),parent.as(ClassEntry)) 
        elsif !klass.as(ClassEntry).parent.nil? && parent
            lc_raise(LcTypeError,convert(:superclass_err) % name)
        elsif klass.as(ClassEntry).parent.nil?
            internal.lc_set_parent_class(klass.as(ClassEntry),Internal::Obj)
        end
        eval_body(body)
        exit_scope
        pop_frame
    end

    protected def define_class(klass,name)
        if klass.is_a? ClassEntry
            if klass.frozen
                lc_raise(LcFrozenError,convert(:frozen_class))
                return nil 
            end
            reopen(klass)
            return klass
        elsif !klass.nil?
            lc_raise(LcTypeError,convert(:not_a_class) % name)
        else
            return internal.lc_build_class(name.as(String))
        end
        nil 
    end

    macro check_name(name,oldName)
        if {{name}}.nil?
            lc_raise(LcNameError,convert(:undefined_const) % {{oldName}},node)
        elsif ! {{name}}.is_a? Structure
            lc_raise(LcTypeError,convert(:not_a_struct) % {{oldName}},node)
        end 
    end

    protected def eval_namespace(node : Node, last = true)
        names = node.getBranches
        first = unpack_name(names[0])
        name  = find(first)
        check_name(name,first)
        (1...names.size - 1).each do |n|
           id   = unpack_name(names[n])
           name = name.as(Structure).symTab.lookUp(id)
           check_name(name,id)
        end
        name = name.as(Structure).symTab.lookUp(unpack_name(names.last)) if last && names.size > 1
        if name
            return internal.unpack_const(name) 
        else 
            lc_raise(LcNameError,convert(:undefined_const) % stringify_namespace(node),node)
            return null 
        end 
    end

    protected def eval_module(node : Node)
        namespace = node.getAttr(NKey::NAME)
        body      = node.getBranches
        name      = namespace.as(Node).getBranches
        if name.size == 1
            name = unpack_name(name[0])
            mod  = find(name)
            mod  = define_module(mod,name)
        else
            scope = eval_namespace(namespace.as(Node),false)
            reopen(scope)
            name = unpack_name(name.last)
            mod  = find_local(name)
            mod  = define_module(mod,name)
        end 
        if mod 
            push_frame(find_file(node),find_line(node),name,mod)
            eval_body(body[0])
            exit_scope
            pop_frame
        end 
    end

    protected def define_module(mod,name)
        if mod.is_a? ModuleEntry
            if mod.frozen 
                lc_raise(LcFrozenError,convert(:frozen_module))
                return nil 
            end
            reopen(mod)
        elsif !mod.nil?
            lc_raise(LcTypeError,convert(:not_a_module) % name)
        else
            return internal.lc_build_module(name.as(String))
        end 
        nil
    end

    protected def eval_void(node : Node) : ::Nil
        name     = node.getAttr(NKey::NAME).as(Node)
        visib    = node.getAttr(NKey::VOID_VISIB)
        branches = node.getBranches
        args     = branches[0]
        arity    = args.getAttr(NKey::VOID_ARITY).as(Intnum)
        body     = branches[1]
        static   = false
        if name.type == NodeType::SELF
            voidName = unpack_name(name.getBranches[0]).as(String)
            receiver = current_scope
            static   = true
        else
            voidName = unpack_name(name).as(String)
            receiver = name.getAttr(NKey::RECEIVER)
            if receiver 
                if receiver.as(Node).type == NodeType::NAMESPACE
                    receiver = eval_namespace(receiver.as(Node))
                    static   = true
                    return nil unless receiver
                elsif receiver 
                    r_name   = unpack_name(receiver.as(Node))
                    receiver = find(r_name)
                    if !receiver
                        lc_raise(LcNameError,convert(:undefined_const) % r_name,node)
                        return nil
                    end
                    static = true
                end
            else 
                receiver = current_scope.as(Structure)
            end 
        end
        if {VoidVisib::PUBLIC,nil}.includes? visib
            if static
                method = internal.lc_define_static_usr_method(
                    voidName,args,receiver.as(Structure),body,arity
                )
            else 
                method = internal.lc_define_usr_method(
                    voidName,args,receiver.as(Structure),body,arity
                )
            end
        else
            visib = visib.as(VoidVisib)
            if static
                method = internal.lc_define_static_usr_method(
                   voidName,args,receiver.as(Structure),body,arity,visib
                )
            else
                method = internal.lc_define_usr_method(
                    voidName,args,receiver.as(Structure),body,arity,visib
                )
            end
        end 
        return nil if @error 
        receiver = receiver.as(Structure)
        if method.static 
            bind_static_method(receiver,voidName,method)
        else 
            bind_method(receiver,voidName,method)
        end
    end

    protected def eval_body(node : Node)
        branches = node.getBranches
        branches.each do |branch|
            outr = eval_stmt(branch.as(Node))
            break if @error
            return outr if outr.is_a? StackFrame
        end
    end

    protected def eval_assign(node : Node)
        branches = node.getBranches
        var      = branches[0]
        expr     = branches[1]
        exprv    = eval_exp(expr).as(Internal::Value)
        if var.type != NodeType::METHOD_CALL
            name  = unpack_name(var)
            if internal.lc_seek_const(current_scope,name)
                lc_raise(LcNameError,"(Dynamic assignment of const '%s')" % name,node)
                return null 
            end
            return null if @error
            if var.type == NodeType::LOCAL_ID
                set_local(name,exprv)
            else 
                obj = current_object
                unless obj.is_a? Structure
                    if obj.as(Internal::ValueR).frozen
                       lc_raise(LcFrozenError,convert(:modify_frozen),node)
                       return null 
                    end 
                end 
                obj.data.addVar(name,exprv.as(Internal::Value))
            end
        else 
            r_node   = var.getAttr(NKey::RECEIVER).as(Node)
            receiver = eval_exp(r_node).as(Internal::Value)
            args     = var.getBranches[1]
            index    = eval_args(args)
            if index.is_a? Tuple 
                index += {exprv}
            else 
                index += [exprv]
            end
            push_frame(find_file(node),find_line(node),"[]=")
            call_fun(receiver,"[]=",index)
        end
        return exprv
    end

    protected def eval_include(node : Node)
        namespace = node.getBranches[0]
        entry     = eval_namespace(namespace)
        return nil if @error
        if entry.is_a? ModuleEntry
            internal.lc_include_module(current_scope,entry)
        else
            lc_raise(LcTypeError,convert(:not_a_module) % stringify_namespace(namespace))
        end 
    end

    protected def eval_const(node : Node)
        branch   = node.getBranches[0]
        branches = branch.as(Node).getBranches
        id       = branches[0]
        expr     = branches[1]
        name     = unpack_name(id)
        val      = eval_exp(expr)
        return nil if @error 
        centry = internal.lc_seek_const(current_scope,name)
        if centry
            lc_raise(LcNameError,"Constant '%s' already defined" % name)
            return nil
        end
        internal.lc_define_const_locally(name,val.as(Internal::Value))
    end

    protected def eval_return(node : Node)
        branch = node.getBranches[0]
        result = eval_exp(branch)
        return null if @error
        frame = pop_frame
        frame.return_val = result.as(Internal::Value)
        return frame 
    end 

    protected def eval_new(node : Node)
        branches  = node.getBranches
        namespace = branches[0]
        args      = branches[1]
        entry     = eval_namespace(namespace)
        if !(entry.is_a? ClassEntry)
            lc_raise(LcTypeError,convert(:not_a_class) % stringify_namespace(namespace),node)
            return null 
        end
        obj  = call_fun(node,entry,"new").as(Internal::Value)
        if internal.lc_obj_responds_to? obj, "init"
            argv = eval_args(args)
            push_frame(find_file(node),find_line(node),"init",obj)
            call_fun(obj,"init",argv)
            return obj 
        else 
            return obj 
        end
    end

    protected def eval_if(node : Node)
        branches  = node.getBranches
        condition = branches[0]
        then_b    = branches[1]
        else_b    = branches[2]?
        if eval_condition(condition)
            out_v = eval_body(then_b)
            return null if @error
            return out_v if out_v.is_a? StackFrame
        elsif else_b
            if else_b.type == NodeType::IF
                out_v = eval_if(else_b.as(Node))
            else
                out_v = eval_body(else_b.as(Node))
            end
            return null if @error
            return out_v if out_v.is_a? StackFrame
        end 
        return null
    end

    protected def eval_while(node : Node)
        branches  = node.getBranches
        condition = branches[0]
        body      = branches[1]
        while eval_condition(condition)
            out_v = eval_body(body)
            return null if @error
            return out_v if out_v.is_a? StackFrame
        end 
        return null
    end

    protected def eval_until(node : Node)
        branches  = node.getBranches
        body      = branches[0]
        condition = branches[1]
        loop do 
            out_v = eval_body(body)
            return null if @error 
            return out_v if out_v.is_a? StackFrame
            return null if eval_condition(condition)           
        end
    end

    protected def eval_select(node : Node)
        branches  = node.getBranches
        condition = branches[0]
        c_value   = eval_exp(condition).as(Internal::Value)
        return null if @error
        opt       = find_opt(branches,c_value)
        return null if @error
        if opt
            out_v = eval_body(opt.as(Node))
            return null if @error || !(out_v.is_a? StackFrame)
            return out_v
        end 
        return null
    end

    protected def find_opt(branches : Array(Node),c : Internal::Value)
        optHash = {} of (Internal::Value | String) => Node
        i       = 1
        _else   = nil
        while i < branches.size 
            optNode = branches[i]
            if optNode.type == NodeType::CASE
                optBranches = optNode.getBranches
                optList     = optBranches[0].getBranches
                optBody     = optBranches[1]
                optList.each do |opt|
                    opt_v = eval_exp(opt)
                    return nil if @error
                    if call_fun(opt,c,"==",opt_v.as(Internal::Value)) == Internal::LcTrue
                        return optBody
                    end
                end
            else 
                body  = optNode.getBranches[0]
                _else = body
            end 
            i += 1
        end
        return _else
    end

    protected def eval_condition(node : Node)
        value = eval_exp(node)
        if value.is_a? Internal::Null || value.is_a? Internal::LcFalse
            return false 
        else 
            return true
        end
    end

    protected def eval_try(node : Node)
        branches  = node.getBranches
        try       = branches[0]
        catch     = branches[1]?
        @try += 1
        out_v     = eval_body(try)
        if @error
            @try -= 1
            if catch 
                catch_branches = catch.getBranches
                id             = catch_branches[0]
                body           = catch_branches[1]
                name           = unpack_name(id)
                set_local(name,@error)
                @error = nil
                out_v  = eval_body(body)
                delete_local(name)
                return out_v if out_v.is_a? StackFrame
                return null
            end
        else 
           return out_v if out_v.is_a? StackFrame
           return null 
        end  
    end

    protected def eval_array(node : Node)
        branches = node.getBranches
        ary      = internal.build_ary(branches.size)
        branches.each do |elem|
            internal.lc_ary_push(ary,eval_exp(elem).as(Internal::Value))
        end
        return ary
    end

    protected def eval_append(node : Node)
        branches = node.getBranches
        obj      = eval_exp(branches[0]).as(Internal::Value)
        value    = eval_exp(branches[1]).as(Internal::Value)
        call_fun(node,obj,"<<",value)
        null 
    end

    protected def eval_range(node : Node)
        branches = node.getBranches
        v1       = branches[0]
        v2       = branches[1]
        left     = eval_exp(v1).as(Internal::Value)
        right    = eval_exp(v2).as(Internal::Value)
        inclusive = (node.type == NodeType::ERANGE) ? false : true
        return internal.build_range(left,right,inclusive)
    end

    protected def eval_matrix(node : Node)
        branches = node.getBranches
        rws      = branches.size 
        cls      = (branches[0]? ? branches[0].getBranches.size : 0)
        matrix   = internal.build_matrix(rws,cls)
        (0...rws).each do |i|
            rows = branches[i].getBranches
            (0...cls).each do |j|
                value = eval_exp(rows[j]).as(Internal::Value)
                break if @error
                internal.lc_set_matrix_index(matrix,i,j,value)
            end
            break if @error
        end
        return matrix
    end

    protected def eval_yield(node : Node)
        
    end

    protected def delete_block_args(list)
        if list
            list.each do |var|
                delete_local(var)
            end
        end
    end

    protected def delete_block_args(frame : StackFrame,list)
       if list
           frame_list = frame.to_unsafe
           list.each do |var|
               frame_list.delete(var)
           end 
        end 
    end

    def lc_yield(*args : Internal::Value)
        block = get_block
        return execute_yield(block,args)
    end

    protected def load_block_args(argv : Node,args)
        arg_list = argv.getBranches
        var_list = [] of String
        arg_list.each_with_index do |arg,i|
            val = args[i]?
            if arg.type == NodeType::ASSIGN
                if val 
                    name = unpack_name(arg.getBranches[0])
                    var_list << name
                    set_local(name,val)
                else 
                    name = unpack_name(arg.getBranches[0])
                    var_list << name
                    eval_assign(arg)
                end 
            else 
                name = unpack_name(arg)
                var_list << name
                if val 
                    set_local(name,val)
                else 
                    set_local(name,null)
                end 
            end
        end 
        return var_list        
    end

    def block_given?
        return (get_block ? true : false)
    end

    protected def eval_yield(node : Node)
        args  = node.getBranches[0]
        block = get_block
        argv  = eval_args(args)
        return null if @error
        value = execute_yield(block,argv)
        return value
    end

    protected def execute_yield(block,args)
        if block .nil?
            lc_raise(LcArgumentError,"No block given")
            return null
        end
        argv  = block.as(Node).getAttr(NKey::BLOCK_ARG)
        push_cloned_frame
        var_list = nil
        if argv 
            var_list = load_block_args(argv.as(Node),args)
        end
        return null if @error
        out_v = eval_body(block.as(Node))
        return null if @error
        if out_v.is_a? StackFrame
            delete_block_args(out_v,var_list)
            return out_v.return_val
        end
        delete_block_args(var_list)
        pop_frame
        return null
    end

    protected def eval_raise(node : Node)
        exp = node.getBranches[0]
        if exp.type == NodeType::NEW
            error = eval_new(exp)
            if internal.lc_is_a(error.as(Internal::Value),Internal::ErrClass)
                lc_raise_e(error,node)
            else 
                lc_raise(LcTypeError,"(Expecting string/error object)",node)
            end
        elsif exp.type == NodeType::STRING 
            msg = exp.getAttr(NKey::VALUE).as(String)
            lc_raise(LcRuntimeError,msg,node)
        elsif exp.type == NodeType::LOCAL_ID || exp.type == NodeType::GLOBAL_ID
            error = eval_exp(exp)
            if internal.lc_is_a(error.as(Internal::Value),Internal::ErrClass)
                lc_raise_e(error,node)
            else 
                lc_raise(LcTypeError,"(Expecting string/error object)",node)
            end
        else 
            lc_raise(LcTypeError,"(Expecting string/error object)",node)
        end
    end

    def lc_raise(code,msg,node)
        backtrace = build_backtrace(node) if node
        if @try == 0
            error = String.build do |err|
                err << code
                err << ": "
                err << msg
                err << backtrace
            end
            send_msg(error)
        else
            @error = internal.build_error(code,msg,backtrace.as(String))
        end
        null
    end

    def lc_raise(code,msg)
        backtrace = @callstack.getBacktrace
        if @try == 0
            error = String.build do |str|
                str << '\n'
                str << code
                str << ": "
                str << msg 
                str << backtrace
            end
            send_msg(error)
        else
            @error = internal.build_error(code,msg,backtrace.as(String)) 
        end 
        null
    end

    protected def lc_raise_e(error,node)
        backtrace = build_backtrace(node) if node
        if @try == 0
            err = String.build do |e|
                e << error.as(Internal::LcError).body
                e << backtrace
            end
            send_msg(err)
        else
            @error = error.as(Internal::LcError)
        end
        null
    end

    @[AlwaysInline]
    def class_of(receiver : Internal::Value)
        return receiver.klass.as(ClassEntry) 
    end

    protected def build_backtrace(node : Node)
        line            = find_line(node)
        file            = find_file(node)
        callstack_trace = @callstack.getBacktrace
        return String.build do |str|
            str << '\n'
            str << "Line: "
            str << line 
            str << '\n'
            str << "In: "
            str << file 
            str << '\n'
            str << callstack_trace
        end
    end

    protected def find_line(node : Node)
        line = node.getAttr(NKey::LINE) 
        node = node.parent
        while (!line) && node
            line = node.getAttr(NKey::LINE)
            node = node.parent
        end 
        return line 
    end

    protected def find_file(node : Node)
        filename = node.getAttr(NKey::FILENAME)
        node = node.parent
        while !filename && node
            filename = node.getAttr(NKey::FILENAME)
            node = node.parent
        end 
        return filename
    end

    protected def stringify_namespace(node : Node)
        names  = node.getBranches
        nspace = String.build do |str|
            names.each do |el|
                str << unpack_name(el) << ':'
            end 
        end
        return nspace[0...nspace.size - 1]
    end
    
end

module LinCAS
    Exec = Eval.new 
end