
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

    # Hash Class Implementation
    #
    # The algorithm bases on https://github.com/crystal-lang/crystal/blob/master/src/hash.cr
    # and it is an adaptation of Crystal hash to a sutable one 
    # for LinCAS which is dinamically typed
    
    HASHER = Crystal::Hasher.new 
    PRIMES = Hash::HASH_PRIMES

    MAX_BUCKET_DEPTH = 5
    
    class Entry 
        @next  : Entry? = nil 
        @prev  : Entry? = nil 
        @fore  : Entry? = nil
        def initialize(@key : Value,@hash : UInt64,@value : Value)
        end
        property key,value,prev,fore
        property "next"
    end

    alias  Entries = Pointer(Entry?)

    class LcHash < BaseC
        @size       = 0.as(IntnumR)
        @capa       = 0.as(IntnumR)
        @buckets    = Entries.null
        @first      : Entry? = nil  
        @last       : Entry? = nil
        property size,buckets,capa,first,last
    end

    macro hash_size(hash)
        lc_cast({{hash}},LcHash).size 
    end

    macro set_hash_size(hash,size)
        lc_cast({{hash}},LcHash).size = {{size}}
    end

    macro hash_capa(hash)
        lc_cast({{hash}},LcHash).capa
    end

    macro set_hash_capa(hash,capa)
        lc_cast({{hash}},LcHash).capa = {{capa}}
    end

    macro hash_last(hash)
        lc_cast({{hash}},LcHash).last
    end

    macro set_hash_last(hash,last)
        lc_cast({{hash}},LcHash).last = {{last}}
    end

    macro hash_first(hash)
        lc_cast({{hash}},LcHash).first
    end

    macro set_hash_first(hash,first)
        lc_cast({{hash}},LcHash).first = {{first}}
    end

    macro resize_hash_capa(hash,capa)
        lc_cast({{hash}},LcHash).buckets = hash_buckets({{hash}}).realloc({{capa}})
        set_hash_capa({{hash}},{{capa}})
        clear_buckets({{hash}},{{capa}})
    end

    macro hash_buckets(hash)
        lc_cast({{hash}},LcHash).buckets
    end

    macro clear_buckets(hash,capa)
        ptr = hash_buckets({{hash}})
        {{capa}}.times { |i| ptr[i] = nil }
    end

    macro new_entry(key,h_key,value)
        Entry.new({{key}},{{h_key}},{{value}}) 
    end
    
    private def self.get_new_capa(hash : LcHash)
        size = hash_size(hash)
        capa = 8
        PRIMES.each do |n_capa|
            return n_capa if capa > size
            capa <<= 1
        end
        lc_raise(LcRuntimeError,"(Hash table too big)")
        return size + 2
    end

    private def self.fast_hash(item : Value)
        if lc_obj_has_internal_m? item,"hash"
            if item.is_a? LcInt
                value = int2num(item)
                {% if flag? (:fast_math) %}
                    return HASHER.int(value).result
                {% else %}
                    if value.is_a? BigInt
                        return value.to_u64 # FIX THIS
                    else 
                        return HASHER.int(value).result
                    end 
                {% end %}
            elsif item.is_a? LcFloat
                return HASHER.float(float2num(item)).result
            elsif item.is_a? LcString
                return HASHER.bytes(string2slice(item)).result
            end 
            return HASHER.int(item.id).result
        end
        value = lc_num_to_cr_i(Exec.lc_call_fun(item,"hash"))
        if value 
            return value.to_u64
        else
            return HASHER.int(item.id).result
        end 
    ensure
        HASHER.reset
    end

    private def self.fast_compare(v1 : Value,v2 : Value)
        return true if v1.id == v2.id 
        if lc_obj_has_internal_m? v1,"=="
            if v1.is_a? LcInt 
                return bool2val(lc_int_eq(v1,v2))
            elsif v1.is_a? LcFloat
                return bool2val(lc_float_eq(v1,v2))
            elsif v1.is_a? LcString
                return bool2val(lc_str_compare(v1,v2))
            #elsif v1.is_a? Matrix 
            #    return lc_matrix_eq(v1,v2)
            end
            return (Exec.lc_call_fun(v1,"==",v2) == lctrue) ? true : false
        end
        return lc_obj_compare(v1,v2)
    end

    private def self.rehash(hash : LcHash)
        n_capa  = get_new_capa(lc_cast(hash,LcHash))
        resize_hash_capa(hash,n_capa)
        entry_list = hash_last(hash)
        buckets    = hash_buckets(hash)
        while entry_list
            h_key           = fast_hash(entry_list.key)
            index           = bucket_index(h_key,n_capa)
            entry_list.next = buckets[index]
            buckets[index]  = entry_list
            entry_list      = entry_list.prev
        end
    end

    def self.build_hash
        return lc_hash_allocator(HashClass)
    end

    def self.lc_hash_allocate(klass : Value)
        hash = LcHash.new
        klass = lc_cast(klass,LcClass)
        hash.klass = klass 
        hash.data  = klass.data.clone 
        hash.id    = hash.object_id
        lc_hash_init(hash)
        return lc_cast(hash,Value)
    end

    hash_allocator = LcProc.new do |args|
        next lc_hash_allocate(*lc_cast(args,T1))
    end

    def self.lc_hash_init(hash : Value)
        set_hash_capa(hash,11)
        resize_hash_capa(hash,11)
    end

    @[AlwaysInline]
    def self.bucket_index(key : UInt64,capa : IntnumR)
        return key % capa 
    end

    def self.insert_item(hash : Value,key : Value,value : Value,capa : IntnumR) : Entry?
        h_key   = fast_hash(key)
        index   = bucket_index(h_key,capa)
        buckets = hash_buckets(hash)
        entry   = buckets[index]
        if entry
            while entry 
                if fast_compare(entry.key,key)
                    entry.value = value
                    return nil 
                end
                if entry.next 
                    entry = entry.next 
                else
                    return entry.next = new_entry(key,h_key,value)
                end  
            end
        end
        return buckets[index] = new_entry(key,h_key,value)
    end

    def self.lc_hash_set_index(hash : Value,key : Value, value : Value) : Value
        size = hash_size(hash)
        capa = hash_capa(hash)
        if size > capa * MAX_BUCKET_DEPTH
            rehash(lc_cast(hash,LcHash)) 
            capa = hash_capa(hash) 
        end  
        entry = insert_item(hash,key,value,capa)
        return value unless entry 
        size += 1
        set_hash_size(hash,size)
        if last = hash_last(hash)
            last.fore  = entry 
            entry.prev = last 
        end
        set_hash_last(hash,entry)
        first = hash_first(hash)
        set_hash_first(hash,entry) unless first
        return value
    end

    hash_set_index = LcProc.new do |args|
        next lc_hash_set_index(*lc_cast(args,T3))
    end

    @[AlwaysInline]
    def self.hash_empty?(hash : Value)
        return (hash_size(hash) == 0) ? true : false 
    end

    @[AlwaysInline]
    def self.lc_hash_empty(hash : Value)
        return val2bool(hash_empty?(hash))
    end

    hash_empty = LcProc.new do |args|
        next lc_hash_empty(*lc_cast(args,T1))
    end

    private def self.fetch_entry_in_bucket(entry : Entry?,key : Value)
        while entry 
            if fast_compare(entry.key,key)
                return entry 
            end
            entry = entry.next 
        end
        return nil
    end

    def self.lc_hash_fetch(hash : Value,key : Value)
        return Null if hash_empty?(hash)
        h_key   = fast_hash(key)
        capa    = hash_capa(hash)
        index   = bucket_index(h_key,capa)
        buckets = hash_buckets(hash)
        entry   = buckets[index]
        entry   = fetch_entry_in_bucket(entry,key)
        return entry ? entry.value : Null
    end

    hash_fetch = LcProc.new do |args|
        next lc_hash_fetch(*lc_cast(args,T2))
    end


    HashClass = internal.lc_build_internal_class("Hash")
    internal.lc_set_parent_class(HashClass,Obj)

    internal.lc_set_allocator(HashClass,hash_allocator)

    internal.lc_add_internal(HashClass,"[]=",hash_set_index,  2)
    internal.lc_add_internal(HashClass,"empty?",hash_empty,   0)
    internal.lc_add_internal(HashClass,"fetch",hash_fetch,    1)
    internal.lc_add_internal(HashClass,"[]",hash_fetch,       1)


end