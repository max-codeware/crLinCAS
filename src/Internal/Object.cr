
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

    class LcObject < BaseC
    end

    def self.boot_main_object
        return internal.lc_obj_new(MainClass)
    end

    def self.lc_obj_new(klass : Value)
        klass = klass.as(ClassEntry)
        obj = LcObject.new
        obj.klass = klass
        obj.data  = klass.data.clone
        return obj.as(Value) 
    end

    def self.lc_obj_init(obj : Value)
        return obj 
    end

    Obj       = internal.lc_build_class_only("Object")
    MainClass = Id_Tab.getRoot.as(ClassEntry)
    internal.lc_set_parent_class(Obj,LcClass)
    internal.lc_set_parent_class(MainClass,Obj)

    internal.lc_add_static(Obj,"new",:lc_obj_new,    0)
    internal.lc_add_internal(Obj,"init",:lc_obj_init,0)

end