

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

module LinCAS::PyHelper
    {% if flag?(:x86_64) %}
        Py_TPFLAGS_TYPE_SUBCLASS    = 1_u64 << 31
        Py_TPFLAGS_UNICODE_SUBCLASS = 1_u64 << 28
    {% else %}
        Py_TPFLAGS_TYPE_SUBCLASS    = 1_u32 << 31
        Py_TPFLAGS_UNICODE_SUBCLASS = 1_u32 << 28
    {% end %}

    macro pyobj_incref(obj)
        Python.Py_IncRef({{obj}})
    end
    
    macro pyobj_decref(obj)
        Python.Py_DecRef({{obj}})
    end

    macro py_fetch_error(ptype,value,btrace)
        Python.PyErr_Fetch({{ptype}},{{value}},{{btrace}})
    end

    macro py_restore_err(ptype,value,btrace)
        Python.PyErr_Restore({{ptype}},{{value}},{{btrace}})
    end

    macro py_err_occurred
        Python.PyErr_Occurred 
    end

    macro string2py(string)
        Python.PyUnicode_DecodeFSDefault({{string}})
    end

    macro pystring2cstring(string)
        Python.PyUnicode_AsUTF8({{string}})
    end

    macro pystring2cstring2(string,size)
        Python.PyUnicode_AsUTF8AndSize({{string}},{{size}})
    end

    macro int2py(int)
        Python.PyLong_FromLong({{int}})
    end

    macro pyint2int(int)
        Python.PyLong_AsLong({{int}})
    end

    macro float2py(float)
        Python.PyFloat_FromDouble({{float}})
    end

    macro pyfloat2float(float)
        Python.PyFloat_AsDouble({{float}})
    end

    macro ccomplex2py(cpx)
        Python.PyComplex_FromCComplex({{cpx}})
    end

    macro pycomplex2c(cpx)
        Python.PyComplex_AsCComplex({{cpx}})
    end

    macro floats2pycomplex(re,im)
        Python.PyComplex_FromDoubles({{re}},{{im}})
    end

    macro pyobj2pystr(obj)
        Python.PyObject_Str({{obj}})
    end

    macro pyobj_attr(obj,attr)
        Python. PyObject_GetAttrString({{obj}},{{attr}})
    end

    macro pyobj_attr2(obj,attr)
        Python. PyObject_GetAttr({{obj}},{{attr}})
    end

    macro pycall(call,args)
        Python.PyObject_CallObject({{call}},{{args}})
    end

    macro pytypeof(obj)
        Python. PyObject_Type({{obj}})
    end

    @[AlwaysInline]
    def pytype_check(obj,type)
        t = pytypeof(obj)
        res = (t == type) || (is_pysubtype(t,type) == 1)
        pyobj_decref(t)
        return res
    end

    macro pytest(obj)
        Python.PyObject_IsTrue({{obj}})
    end

    macro pyobj_is_instance(obj,klass)
        Python.PyObject_IsInstance({{obj}},klass)
    end

    macro pyimport0(name)
        Python.PyImport_Import({{name}})
    end

    macro pyimport1(name,globals,locals,fromlist)
        Python.PyImport_ImportModuleEx({{name}},{{globals}},{{locals}},{{fromlist}})
    end

    macro get_pymodule_dict(mod)
        Python.PyModule_GetDict({{mod}})
    end

    macro new_pytuple(size)
        Python.PyTuple_New({{size}})
    end

    macro set_pytuple_item(tuple,index,item)
        Python.PyTuple_SetItem({{tuple}},{{index}},{{item}})
    end

    macro pyimethod_f(m)
        Python.PyInstanceMethod_Function({{m}})
    end

    macro pymethod_f(m)
        Python.PyMethod_Function({{m}})
    end

    macro pymethod_receiver(m)
        Python.PyMethod_Self({{m}})
    end

    macro pydict_get0(dict,name)
        Python.PyDict_GetItem({{dict}},{{name}})
    end

    macro pydict_get1(dict,name)
        Python.PyDict_GetItemString({{dict}},{{name}})
    end

    macro is_pysubtype(a,b)
        Python.PyType_IsSubtype({{a}},{{b}})
    end

    macro pytype_flags(t)
        Python.PyType_GetFlags({{t}})
    end

    DICT      = Python.PyEval_GetBuiltins # This is a bit unsafe
    PyInt     = pydict_get1(DICT,"int")
    PyFloat   = pydict_get1(DICT,"float")
    PyType    = pydict_get1(DICT,"type")
    PyString  = pydict_get1(DICT,"str")
    PyStaticM = pydict_get1(DICT,"staticmethod")

    @[AlwaysInline]
    def pytype_fast_subclass(obj,f)
        t = pytypeof(obj)
        res = (pytype_flags(t) & f) != 0
        pyobj_decref(t)
        return res
    end
    
    macro is_pyfloat(obj)
        pytype_check({{obj}},PyFloat)
    end

    macro is_pyfloat_abs(obj)
        {{obj}} == PyFloat
    end

    macro is_pyint(obj)
        pytype_check({{obj}},PyInt)
    end

    macro is_pyint_abs(obj)
        {{obj}} == PyInt
    end

    macro is_pytype(obj)
        pytype_fast_subclass({{obj}},Py_TPFLAGS_TYPE_SUBCLASS)
    end

    @[AlwaysInline]
    def is_pytype_abs(obj)
        t = pytypeof(obj)
        res = t == PyType
        pyobj_decref(t)
        res
    end

    macro is_pystring(obj)
        pytype_fast_subclass({{obj}},Py_TPFLAGS_UNICODE_SUBCLASS)
    end

    @[AlwaysInline]
    def is_pystring_abs(obj)
        t = pytypeof(obj)
        res = t == PyString
        pyobj_decref(t)
        res
    end

    @[AlwaysInline]
    def is_pymodule(obj)
        m = Python.PyModule_New("dummy")
        t = pytypeof(m)
        pyobj_decref(m)
        res = pytype_check(obj,t)
        pyobj_decref(t)
        return res
    end

    macro is_pycallable(obj)
        Python.PyCallable_Check({{obj}}) == 1
    end

    macro is_pystatic_method(obj)
        pytype_check({{obj}},PyStaticM)
    end

    macro is_pyfunction(obj)
        Python.PyFunction_Check({{obj}}) == 1
    end

    macro is_pymethod(obj)
        Python.PyMethod_Check({{obj}}) == 1
    end

    macro is_pyimethod(obj)
        Python.PyInstanceMethod_Check({{obj}}) == 1
    end

    macro is_pydict(obj)
        Python.PyDict_Check({{obj}}) == 1
    end

    macro is_pydict_abs(obj)
        Python.PyDict_CheckExact({{obj}}) == 1
    end

end