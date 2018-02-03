
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

module LinCAS::Internal
    
    def 
    self.lc_define_usr_method(
        name, args : Node, owner : LinCAS::Structure, code : Node,
        arity : Intnum, visib : VoidVisib = VoidVisib::PUBLIC
    )
        m       = LinCAS::MethodEntry.new(name.as(String),visib)
        m.args  = args
        m.owner = owner
        m.code  = code
        m.arity = arity
        return m 
    end

    def 
    self.lc_define_static_usr_method(
        name,args : Node, owner : LinCAS::Structure, code : Node, 
        arity : Intnum, visib : VoidVisib = VoidVisib::PUBLIC 
    )
        m        = self.lc_define_usr_method(name,args,owner,code,arity,visib)
        m.static = true
        return m
    end

    def self.lc_define_internal_method(name, owner : LinCAS::Structure, code, arity)
        m          = LinCAS::MethodEntry.new(name, VoidVisib::PUBLIC)
        m.internal = true
        m.owner    = owner
        m.code     = code
        m.arity    = arity 
        return m
    end

    def self.lc_define_internal_static_method(name, owner : LinCAS::Structure, code, arity)
        m        = self.lc_define_internal_method(name,owner,code,arity)
        m.static = true
        return m
    end

    def self.lc_define_internal_singleton_method(name,owner : LinCAS::Structure,code,arity)
        m           = self.lc_define_internal_method(name,owner,code,arity)
        m.singleton = true
        return m
    end

    def self.lc_define_internal_static_singleton_method(name,owner : LinCAS::Structure,code,arity)
        m           = self.lc_define_internal_static_method(name,owner,code,arity)
        m.singleton = true
        return m
    end

    macro define_method(name,owner,code,arity)
        internal.lc_define_internal_method(
            {{name}},{{owner}},{{code}},{{arity}}
        )
    end

    macro define_static(name,owner,code,arity)
        internal.lc_define_internal_static_method(
            {{name}},{{owner}},{{code}},{{arity}}
        )
    end

    macro define_singleton(name,owner,code,arity)
        internal.lc_define_internal_singleton_method(
            {{name}},{{owner}},{{code}},{{arity}}
        )
    end

    macro define_static_singleton(name,owner,code,arity)
        internal.lc_define_internal_static_singleton_method(
            {{name}},{{owner}},{{code}},{{arity}}
        )
    end

    def self.seek_method(receiver : Structure, name)
        method = seek_instance_method(receiver,name)
        if method != 0
            return method 
        else 
            parent = parent_of(receiver) 
            while parent 
                method = seek_instance_method(parent,name)
                return method if method != 0
                parent = parent_of(parent)
            end
        end
        return method
    end

    def self.seek_instance_method(receiver : Structure,name)
        method = receiver.methods.lookUp(name)
        if method.is_a? MethodEntry
            method = method.as(MethodEntry)
            if !method.static
                case method.visib 
                    when VoidVisib::PUBLIC
                        return method
                    when VoidVisib::PROTECTED
                        return 1
                    when VoidVisib::PRIVATE 
                        return 2
                end
            else
                return 0
            end
        else
            return 0
        end
    end

    def self.seek_static_method(receiver : Structure, name)
        method    = seek_static_method2(receiver,name)
        if method.is_a? MethodEntry
            return method
        else
            if receiver.is_a? ClassEntry
                parent = parent_of(receiver)
                while parent 
                    method = seek_static_method2(parent,name)
                    return method if method.is_a? MethodEntry
                    parent = parent_of(parent) 
                end
            end
        end
        return 0
    end
    
    def self.seek_static_method2(receiver : Structure, name : String)
        method = receiver.methods.lookUp(name)
        if !method.nil?
            method = method.as(MethodEntry)
            return method if method.static
        end
        return 0
    end

    def self.lc_obj_responds_to?(obj : Value,method : String)
        if obj.is_a? Structure 
            m = internal.seek_static_method(obj.as(Structure),method)
        else 
            m = internal.seek_method(obj.as(ValueR).klass,method)
        end
        return m.is_a? MethodEntry
    end

    def self.lc_copy_methods_as_instance_in(sender : Structure, receiver : Structure)
        smtab = sender.methods
        rmtab = receiver.methods
        smtab.each_key do |name|
            internal.insert_method_as_instance(smtab[name].as(MethodEntry),rmtab)
        end
    end

    def self.lc_copy_methods_as_static_in(sender : Structure, receiver : Structure)
        smtab = sender.methods
        rmtab = receiver.methods
        smtab.each_key do |name|
            internal.insert_method_as_static(smtab[name].as(MethodEntry),rmtab)
        end
    end

    def self.insert_method_as_instance(method : MethodEntry, r : SymTab)
        if !method.static 
            r.addEntry(method.name,method)
        end
    end

    def self.insert_method_as_static(method : MethodEntry, r : SymTab)
        if !method.static 
            method.static = true
            r.addEntry(method.name,method)
        end
    end


end