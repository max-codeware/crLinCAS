
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

    struct LcInt < LcNum
        @val : Intnum
        def initialize(@val)
        end
        getter val
    end

    @[AlwaysInline]
    def self.num2int(num : Intnum)
        return build_int(num)
    end

    @[AlwaysInline]
    def self.int2num(int : Value)
        return int.as(LcInt).val
    end 

    def self.build_int(value : Intnum)
        int       = LcInt.new(value)
        int.klass = IntClass
        int.data  = IntClass.data.clone
        int.frozen = true
        return int.as(Value)
    end 

    def self.lc_int_sum(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            return internal.num2int(int2num(n1) + int2num(n2))
        else
            return internal.lc_num_coerce(n1,n2,"+")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_sub(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            return internal.num2int(int2num(n1) - int2num(n2))
        else
            return internal.lc_num_coerce(n1,n2,"-")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_mult(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            return internal.num2int(int2num(n1) * int2num(n2))
        else
            return internal.lc_num_coerce(n1,n2,"*")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_idiv(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            if int2num(n2) == 0
                lc_raise(LcZeroDivisionError,"(Division by 0)")
                return positive_num(n1) ? LcInfinity : LcNinfinity
            end
            return internal.num2int(int2num(n1) / int2num(n2))
        else
            return internal.lc_num_coerce(n1,n2,"\\")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_fdiv(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            if int2num(n1) == 0
                return positive_num(n1) ? LcInfinity : LcNinfinity
            end
            return internal.num2float(int2num(n1) / int2num(n2).to_f)
        else
            return internal.lc_num_coerce(n1,n2,"/")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_power(n1 : Value, n2 : Value)
        if n2.is_a? LcInt 
            return internal.num2int(int2num(n1) ** int2num(n2))
        else
            return internal.lc_num_coerce(n1,n2,"^")
        end
        # Should never get here
        return Null
    end

    def self.lc_int_odd(n : Value)
        if int2num(n).odd? 
            return lctrue
        else 
            return lcfalse
        end 
    end

    def self.lc_int_even(n : Value)
        return internal.lc_bool_invert(lc_int_odd(n))
    end

    def self.lc_int_to_s(n : Value)
        return internal.build_string(int2num(n).to_s)
    end

    def self.lc_int_to_f(n : Value)
        return internal.num2float(int2num(n).to_f)
    end

    def self.lc_int_invert(n : Value)
        return internal.build_int(- int2num(n))
    end

    

    IntClass = internal.lc_build_class_only("Integer")
    internal.lc_set_parent_class(IntClass,NumClass)

    internal.lc_add_internal(IntClass,"+",:lc_int_sum,  1)
    internal.lc_add_internal(IntClass,"-",:lc_int_sub,  1)
    internal.lc_add_internal(IntClass,"*",:lc_int_mult, 1)
    internal.lc_add_internal(IntClass,"\\",:lc_int_idiv,1)
    internal.lc_add_internal(IntClass,"/",:lc_int_fdiv, 1)
    internal.lc_add_internal(IntClass,"^",:lc_int_power,1)
    internal.lc_add_internal(NumClass,"odd",:lc_int_odd,       0)
    internal.lc_add_internal(NumClass,"even",:lc_int_even,     0)
    internal.lc_add_internal(IntClass,"invert",:lc_int_invert, 0)
    internal.lc_add_internal(IntClass,"to_s",:lc_int_to_s,     0)
    internal.lc_add_internal(IntClass,"to_f",:lc_int_to_f,     0)
    
end