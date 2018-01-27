
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

    STR_MAX_CAPA = 3000

    class LcString < BaseC
        def initialize
            @str_ptr = Pointer(LibC::Char).null
            @size    = 0
        end
        setter str_ptr
        setter size
        getter str_ptr
        getter size
    end 

    macro set_size(lcStr,size)
        {{lcStr}}.as(LcString).size = {{size}}
    end

    macro str_size(lcStr)
        {{lcStr}}.as(LcString).size.as(Int32)
    end

    macro pointer_of(value)
        {{value}}.as(LcString).str_ptr 
    end

    macro resize_str_capacity(lcStr,value)
        st_size    = str_size({{lcStr}})
        final_size = st_size + {{value}}
        if final_size > STR_MAX_CAPA
            lc_raise(LcIndexError, "String size too big")
            return Null
        else
            {{lcStr}}.as(LcString).str_ptr = pointer_of({{lcStr}}).realloc(final_size.to_i)
            set_size({{lcStr}},final_size)
        end 
    end

    macro str_add_char(lcStr,index,char)
        pointer_of({{lcStr}})[{{index}}] = {{char}}
    end

    macro str_char_at(lcStr,index)
        pointer_of({{lcStr}})[{{index}}]
    end

    macro str_shift(str,to,index,length)
        (1..{{to}}).each do |i|
            char = str_char_at({{str}},{{index}} + {{to}} - i)
            str_add_char({{str}},{{length}} - i,char)
        end 
    end

    def self.string2cr(value : Value)
        value = value.as(LcString)
        ptr   = value.str_ptr
        size  = value.size
        return String.new(pointer_of(value))
    end

    def self.new_string
        str   = LcString.new
        str.klass = StringClass
        str.data  = StringClass.data.clone
        return  str 
    end

    def self.build_string(value)
        str   = new_string
        internal.lc_init_string(str,value)
        return str.as(Value)
    end

    def self.build_string(value : LibC::Char)
        str = new_string
        resize_str_capacity(str,1)
        pointer_of(str)[0] = value 
        return str.as(Value)
    end

    def self.build_string(value : LibC::Char*)
        str = new_string
        strlen = LibC.strlen(value)
        resize_str_capacity(str,strlen)
        pointer_of(str).move_from(value,strlen)
        return str 
    end
    
    # Initializes a new string trough the keyword 'new' or just
    # assigning it. This is the 'init' method of the class
    # ```
    # # str = "Foo" #=> "Foo"
    # ```
    #
    # * argument:: string struct to initialize
    # * argument:: initial string value
    def self.lc_init_string(lcStr : Value, value : (Value | String | LibC::Char))
        # To implement: argument check
        lcStr = lcStr.as(LcString)
        if value.is_a? LcString
            resize_str_capacity(lcStr,str_size(value))
            pointer_of(lcStr).copy_from(value.str_ptr,str_size(value))
        elsif value.is_a? String
            resize_str_capacity(lcStr,value.as(String).size)
            pointer_of(lcStr).move_from(value.to_unsafe,value.size)
        else
            lc_raise(
                LcTypeError,
                "No implicit conversion of #{lc_typeof(value.as(Value))} into String"
            )
            return Null
        end 
    end

    # Concatenates two strings.
    # This method can be invoked in two ways:
    # ```
    # foo    := "Foo"
    # bar    := "Bar"
    # foobar := foo + bar
    # # same as:
    # foobar := foo.concat(bar)
    # ```
    #
    # * argument:: first string struct to concatenate
    # * argument:: second string struct to concatenate
    # * returns:: new string struct
    def self.lc_str_concat(lcStr : Value, str : Value)
        unless str.is_a? LcString
            lc_raise(
                LcTypeError,
                "No implicit conversion of #{lc_typeof(str)} into String"
            )
            return Null
        end
        concated_str = build_string("")
        strlen1      = str_size(lcStr)
        strlen2      = str_size(str)
        strlen_tot   = strlen1 + strlen2
        resize_str_capacity(concated_str,strlen_tot)
        pointer_of(concated_str).copy_from(pointer_of(lcStr),strlen1)
        (pointer_of(concated_str) + strlen1).copy_from(pointer_of(str),strlen2)
        return concated_str
    end

    # Performs a multiplication between a string and a number
    # ```
    # bark   := "Bark"
    # bark_3 := bark * 3 #=> "BarkBarkBark"
    def self.lc_str_multiply(lcStr : Value, times : Value)
        new_str = build_string("")
        strlen  = str_size(lcStr)
        tms     = internal.lc_num_to_cr_i(times)
        return Null unless tms.is_a? Number 
        resize_str_capacity(new_str,strlen * tms)
        set_size(new_str,strlen * tms)
        tms.times do |n|
            (pointer_of(new_str) + n * strlen).copy_from(pointer_of(lcStr),strlen)
        end
        return new_str
    end 

    # Checks if a substring is contained in another one.
    # It works making a call like this:
    # ```
    # str := "A cat on the roof"
    # cat := "Cat"
    # str.include(cat)   #=> true
    # str.include("bed") #=> false
    # ```
    #
    # * argument:: string on which the method is called
    # * argument:: string to be searched
    # * returns:: true if the two strings equal; false else;
    def self.lc_str_include(str1 : Value ,str2 : Value)
        unless str2.is_a? LcString
            lc_raise(
                LcTypeError,
                "No implicit conversion of #{lc_typeof(str2)} into String"
            )
            return Null
        end
        s_ptr = libc.strstr(pointer_of(str1),pointer_of(str2))
        if s_ptr.null?
             return lcfalse
        end
        return lctrue
    end

    # Compares two strings or a string with another object
    # ```
    # bar := "Bar"
    # foo := "Foo"
    # bar == bar #=> true
    # bar == foo #=> false
    # bar == 2   #=> false
    # ```
    #
    # * argument:: string on which the method is called
    # * argument:: string to be compared
    # * returns:: true if the two strings equal; false else;
    def self.lc_str_compare(str1 : Value, str2)
        return lcfalse unless str2.is_a? LcString
        return lcfalse if str_size(str1) != str_size(str2)
        return internal.lc_str_include(str1,str2)
    end

    # Same as lc_str_compare, but it checks if two strings are different
    def self.lc_str_icompare(str1 : Value, str2 : Value)
        unless str2.is_a? LcString
            lc_raise(
                LcTypeError,
                "No implicit conversion of #{lc_typeof(str2)} into String"
            )
            return Null
        end
        return lc_bool_invert(internal.lc_str_compare(str1,str2))
    end

    # Clones a string
    #
    # ```
    # a := "Foo"
    # b := a         # b and a are pointing to the same object
    # # Now b and c are going to point to two different objects
    # c := a.clone() #=> "Foo"
    # ```
    #
    # * argument:: string to clone
    # * returns:: new LcString*
    def self.lc_str_clone(str : Value)
        return internal.build_string(str)
    end

    # Access the string characters at the given index
    # ```
    # str := "A quite long string"
    # str[0]    #=> "A"
    # str[8]    #=> "l"
    # str[2..6] #=> "quite"
    # ```
    #
    # * argument:: string to access
    # * argument:: index
    def self.lc_str_index(str : Value, index)
        if index.is_a? LcRange
            strlen = str_size(str)
            return Null if index.left > index.right 
            left    = index.left 
            right   = index.right
            return Null if strlen < left
            return build_string("") if strlen == left
            range_size = right - left + (index.inclusive ? 1 : 0)
            if strlen < left + range_size -1 
                range_size = str_size(str) - left 
            end
            new_str = new_string
            resize_str_capacity(new_str, range_size)
            pointer_of(new_str).copy_from(pointer_of(str) + left,range_size)
            return new_str
        else
            x = internal.lc_num_to_cr_i(index)
            if x 
                if x > str_size(str) - 1
                    return Null 
                else
                    return internal.build_string(str_char_at(str,x))
                end
            end
        end
    end

    # Inserts a second string in the current one
    # ```
    # a := "0234"
    # a.insert(1,"1") #=> "01234"
    # a.insert(5,"5") #=> "012345"
    # a.insert(7,"6") #=> Raises an error
    # ```
    # * argument:: string on which inserting the second one
    # * argument:: index the second string must be inserted at
    # * argument:: string to insert
    def self.lc_str_insert(str : Value, index : Value, value : Value)
        x = internal.lc_num_to_cr_i(index)
        return Null unless x.is_a? Number  
        if x > str_size(str)
            lc_raise(LcIndexError,"(index #{x} out of String)")
            return Null
        else 
            unless value.is_a? LcString
                lc_raise(
                    LcTypeError,
                    "No implicit conversion of #{lc_typeof(value)} into String"
                ) 
                return Null 
            end
            st_size    = str_size(str)
            val_size   = str_size(value)
            final_size = 0
            resize_str_capacity(str,val_size)
            str_shift(str,(st_size - x).abs,x,final_size)
            (pointer_of(str) + x).copy_from(pointer_of(value),val_size)
        end
        return str
    end

    # Sets a char or a set of chars in a specified index
    # ```
    # a    := "Gun"
    # a[0] := "F"    #=> "Fun"
    # a[2] := "fair" #=> "Funfair"
    # a[8] := "!"    #=> Raises an error
    # ```
    #
    # * argument:: string on which the method was invoked
    # * argument:: index to insert the character at
    # * argument:: string to assign
    def self.lc_str_set_index(str : Value,index : Value, value : Value)
        x = internal.lc_num_to_cr_i(index)
        return Null unless x.is_a? Number  
        if x > str_size(str)
            lc_raise(LcIndexError,"(Index #{x} out of String)")
        else
            unless value.is_a? LcString
                lc_raise(
                    LcTypeError,
                    "No implicit conversion of #{lc_typeof(value)} into String"
                ) 
                return Null 
            end
            st_size  = str_size(str)
            val_size = str_size(value)
            if val_size > 1
                final_size = 0
                resize_str_capacity(str,val_size - 1)
                (pointer_of(str) + (x + val_size - 1)).copy_from(pointer_of(str) + x,val_size - 1)
                (pointer_of(str) + x - 1).copy_from(pointer_of(value),val_size)
            else 
                str_add_char(pointer_of(str),x,str_char_at(value,0))
            end
        end 
        return Null 
    end

    # Returns the string size
    # ```
    # a := "Hello, world"
    # a.size() #=> 12
    # ```
    #
    # * argument:: string the method was called on
    def self.lc_str_size(str : Value)
        return num2int(str_size(str))
    end

    # Performs the upcase on the whole string overwriting the original one
    # ```
    # "foo".o_upcase() #=> "FOO"
    # ```
    #
    # * argument:: the string the method was called on
    def self.lc_str_upr_o(str : Value)
        strlen = str_size(str)
        ptr     = pointer_of(str)
        ptr.map!(strlen) do |char|
            char.unsafe_chr.upcase.ord.to_u8
        end
        return str
    end

    # Performs the upcase on the whole string 
    # without overwriting the original one
    # ```
    # "foo".o_upcase() #=> "FOO"
    # ```
    #
    # * argument:: the string the method was called on
    # * returns:: a new upcase string
    def self.lc_str_upr(str : Value)
        strlen = str_size(str)
        ptr    = Pointer(LibC::Char).malloc(strlen)
        s_ptr  = pointer_of(str)
        (0...strlen).each do |i|
            ptr[i] = s_ptr[i].unsafe_chr.upcase.ord.to_u8
        end
        return build_string(ptr)
    end

    # Performs the downcase on the whole string overwriting the original one
    # ```
    # "FOO.o_lowcase() #=> "foo"
    # ```
    #
    # * argument:: the string the method was called on
    def self.lc_str_lwr_o(str : Value)
        strlen = str_size(str)
        ptr     = pointer_of(str)
        ptr.map!(strlen) do |char|
            char.unsafe_chr.downcase.ord.to_u8
        end
        return str
    end

    # Performs the downcase on the whole string 
    # without overwriting the original one
    # ```
    # "FOO.o_lowcase() #=> "foo"
    # ```
    #
    # * argument:: the string the method was called on
    # * returns:: a new lowercase string
    def self.lc_str_lwr(str : Value)
        strlen = str_size(str)
        ptr    = Pointer(LibC::Char).malloc(strlen)
        s_ptr  = pointer_of(str)
        (0...strlen).each do |i|
            ptr[i] = s_ptr[i].unsafe_chr.downcase.ord.to_u8
        end
        return build_string(ptr)
    end


    # Splits a string according to a specific delimiter, returning an array
    # ```
    # a := "a,b,c,d"
    # a.split(",") #=> ["a","b","c","d"]
    # ```
    #
    # * argument:: string the method was called on
    # * argument:: delimiter
    # * returns:: array containing the splitted substrings
    def self.lc_str_split(str1 : Value, str2 : Value = build_string(" "))
        unless str2.is_a? LcString
            lc_raise(
                LcTypeError,
                "No implicit conversion of #{lc_typeof(str2)} into String"
            ) 
            return Null 
        end 
        strlen  = str_size(str1)
        strlen2 = str_size(str2)
        ptr     = Pointer(LibC::Char).malloc(strlen).copy_from(pointer_of(str1),strlen)
        ptr2    = pointer_of(str2)
        ary = build_ary_new nil 
        beg = 0
        final_address = ptr + strlen
        while beg < strlen
            tmp = libc.strtok(ptr.clone,ptr2)
            if tmp.null? 
                lc_ary_push(ary,str1)
                return ary 
            end 
            str = build_string(tmp)
            lc_ary_push(ary,str)
            beg += libc.strlen(tmp) + strlen2
            ptr = Pointer(LibC::Char).malloc(strlen).copy_from(
                pointer_of(str1) + beg ,strlen - beg
            ) unless beg > strlen  
        end
        return ary 
    end

    def self.lc_str_to_i(str : Value)
        return num2int(libc.strtol(pointer_of(str),Pointer(LibC::Char).null,10))
    end

    def self.lc_str_to_f(str : Value)
        return num2float(libc.strtod(pointer_of(str),Pointer(LibC::Char*).null))
    end
        





    StringClass = internal.lc_build_class_only("String")
    internal.lc_set_parent_class(StringClass, Obj)

    internal.lc_add_internal(StringClass,"+",      :lc_str_concat,  1)
    internal.lc_add_internal(StringClass,"concat", :lc_str_concat,  1)
    internal.lc_add_internal(StringClass,"*",      :lc_str_multiply,1)
    internal.lc_add_internal(StringClass,"includes",:lc_str_include,1)
    internal.lc_add_internal(StringClass,"==",     :lc_str_compare, 1)
    internal.lc_add_internal(StringClass, "<>",    :lc_str_icompare,1)
    internal.lc_add_internal(StringClass, "!=",    :lc_str_icompare,1)
    internal.lc_add_internal(StringClass,"clone",  :lc_str_clone,   0)
    internal.lc_add_internal(StringClass,"[]",     :lc_str_index,   1)
    internal.lc_add_internal(StringClass,"[]=",    :lc_str_set_index,2)
    internal.lc_add_internal(StringClass,"insert", :lc_str_insert,  2)
    internal.lc_add_internal(StringClass,"size",   :lc_str_size,    0)
    internal.lc_add_internal(StringClass,"o_upcase",:lc_str_upr_o,  0)
    internal.lc_add_internal(StringClass,"upcase", :lc_str_upr,     0)
    internal.lc_add_internal(StringClass,"o_lowcase",:lc_str_lwr_o, 0)
    internal.lc_add_internal(StringClass,"lowcase",:lc_str_lwr,     0)
    internal.lc_add_internal(StringClass,"split",  :lc_str_split,   1)
    internal.lc_add_internal(StringClass,"to_i",   :lc_str_to_i,    0)
    internal.lc_add_internal(StringClass,"to_f",   :lc_str_to_f,    0)


end