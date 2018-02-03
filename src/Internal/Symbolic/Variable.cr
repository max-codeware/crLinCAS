
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

    struct Variable < BaseS

        getter name

        def initialize(@name : String)
            super()
        end

        def +(obj : Variable)
            return Sum.new(num2sym(2),self) if self == obj 
            return nil unless self.top 
            return Sum.new(self,obj)
        end

        @[AlwaysInline]
        def +(obj : BinaryOp)
            return obj + self
        end

        @[AlwaysInline]
        def +(obj)
            return nil unless self.top
            return Sum.new(self,obj).reduce
        end

        def -(obj : Variable)
            return num2sym(0) if self == obj
            return nil unless self.top
            return Sub.new(self,obj)
        end

        @[AlwaysInline]
        def -(obj)
            return nil unless self.top
            return Sub.new(self,obj).reduce
        end

        @[AlwaysInline]
        def -
            return Negative.new(self)
        end

        def *(obj : Variable)
            return Power.new(self,num2sym(2)) if self == obj 
            return nil unless self.top
            return Product.new(self,obj)
        end

        @[AlwaysInline]
        def *(obj : BinaryOp)
            return obj * self 
        end

        @[AlwaysInline]
        def *(obj : Snumber)
            return nil unless self.top
            return Product.new(obj, self)
        end

        @[AlwaysInline]
        def *(obj)
            return nil unless self.top
            return Product.new(self,obj).reduce
        end

        def /(obj : Variable)
            return num2sym(1) if self == obj 
            return nil unless self.top
            return Division.new(self,obj)
        end 

        @[AlwaysInline]
        def /(obj : BinaryOp)
            return nil unless self.top
            return Division.new(self,obj).reduce
        end

        @[AlwaysInline]
        def /(obj)
            return nil unless self.top
            return Division.new(self,obj).reduce
        end

        @[AlwaysInline]
        def **(obj)
            return nil unless self.top
            return Power.new(self,obj)
        end

        @[AlwaysInline]
        def reduce
            return self 
        end

        def diff(obj)
            return num2sym(1) if self == obj 
            return num2sym(0)
        end

        def eval(dict)

        end

        @[AlwaysInline]
        def to_s(io)
            io << @name 
        end
        
        @[AlwaysInline]
        def to_s
            return @name 
        end

        def ==(obj)
            return false unless obj.is_a? Variable
            return @name == name 
        end

        @[AlwaysInline]
        def depend?(obj)
            return self == obj 
        end

    end

end