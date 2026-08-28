class ArrayDeque
{
    static MAX_ARRAY_SIZE := 2147483639
    
    __new(numElements := 16)
    {
        numElements := (numElements < 1) ? 1 : numElements
        this.elements := []
        this.elements.length := numElements
        this.head := 0
        this.tail := 0
    }
    
    addFirst(e)
    {
        if e is Java.Null
            throw NoSuchElementException("")
        es := this.elements
        es[(this.head := (this.head - 1) & (es.length - 1)) + 1] := e
        if this.head == this.tail
            this.doubleCapacity()
    }
    
    arraycopy(src, srcPos, dest, destPos, length)
    {
        loop length
        {
            try
                dest[destPos + a_index] := src[srcPos + a_index]
        }
    }
    
    clear()
    {
        numElements := this.elements.length
        this.elements := []
        this.elements.length := numElements
        this.head := 0
        this.tail := 0
    }
    
    descendingIterator()
    {
        return ArrayDeque.DescendingIterator(this)
    }
    
    doubleCapacity()
    {
        p := this.head
        n := this.elements.length
        r := n - p
        newCapacity := n << 1
        if (newCapacity < 0)
            throw IllegalStateException("Sorry, deque too big")
        a := ArrayDeque(newCapacity)
        this.arraycopy(this.elements, p, a.elements, 0, r)
        this.arraycopy(this.elements, 0, a.elements, r, p)
        this.elements := a.elements
        this.head := 0
        this.tail := n
    }
    
    getLast()
    {
        es := this.elements
        e := ArrayDeque.elementAt(es, (this.tail - 1) & (es.length - 1))
        if (e is Java.Null)
            throw NoSuchElementException("")
        else
            return e
    }
    
    grow(needed)
    {
        oldCapacity := this.elements.length
        jump := oldCapacity < 64 ? oldCapacity + 2 : oldCapacity >> 1
        if (jump < needed || (newCapacity := oldCapacity + jump) - 2147483639 > 0)
            newCapacity := this.newCapacity(needed, jump)
        newSpace := newCapacity - oldCapacity
        this.head += newSpace
        this.elements.length := newCapacity
    }
    
    newCapacity(needed, jump)
    {
        oldCapacity := this.elements.length
        minCapacity := 0
        if ((minCapacity := oldCapacity + needed) - 2147483639 > 0)
        {
            if (minCapacity < 0)
                throw IllegalStateException("Sorry, deque too big")
        }
        else if needed > jump
            return minCapacity
        else
            return oldCapacity + jump - 2147483639 < 0 ? oldCapacity + jump : 2147483639
    }
    
    peek()
    {
        return this.peekFirst()
    }
    
    peekFirst()
    {
        return ArrayDeque.elementAt(this.elements, this.head)
    }
    
    pollFirst()
    {
        e := ArrayDeque.elementAt(es := this.elements, h := this.head)
        es.delete(h + 1)
        this.head := (h + 1) & (this.elements.length - 1)
        return e
    }
    
    pop()
    {
        return this.removeFirst()
    }
    
    push(e)
    {
        this.addFirst(e)
    }
    
    removeFirst()
    {
        e := this.pollFirst()
        if e is Java.Null
            throw NoSuchElementException("")
        return e
    }
    
    size()
    {
        return ArrayDeque.sub(this.tail, this.head, this.elements.length)
    }
    
    static dec(i, modulus)
    {
        --i
        if (i < 0)
            i := modulus - 1
        return i
    }
    
    static elementAt(es, i)
    {
        try
            ret := es[i + 1]
        catch
            ret := Java.Null()
        return ret
    }
    
    static nonNullElementAt(es, i)
    {
        try
            ret := es[i + 1]
        catch
            throw ConcurrentModificationException("")
        return ret
    }
    
    static inc(i, modulus)
    {
        ++i
        if (i >= modulus)
            i := 0
        return i
    }
    
    static sub(i, j, modulus)
    {
        if ((i -= j) < 0)
            i += modulus
        return i
    }
    
    class DescendingIterator
    {
        __new(outer)
        {
            this.outer := outer
            this.remaining := this.outer.size()
            this.cursor := ArrayDeque.dec(this.outer.tail, this.outer.elements.length)
            this.lastRet := -1
        }
        
        hasNext()
        {
            return this.remaining > 0
        }
        
        next()
        {
            es := this.outer.elements
            e := ArrayDeque.nonNullElementAt(es, this.cursor)
            this.cursor := ArrayDeque.dec(this.lastRet := this.cursor, es.length)
            --this.remaining
            return e
        }
    }
}

class ArrayList
{
    __new(args*)
    {
        this.arr := args
    }
    
    __enum(iternum := 1)
    {
        return this.arr.__enum(iternum)
    }
    
    __item[index]
    {
        get => this.arr[index]
        set => this.arr[index] := value
    }
    
    add(args*)
    {
        if args.length == 1
        {
            e := args[1]
            this.arr.push(e)
        }
        else if args.length == 2
        {
            index := args[1]
            element := args[2]
            this.arr.insertat(index + 1, element)
        }
        return true
    }
    
    contains(o)
    {
        if o is array
            o := ArrayList(o*)
        else if !(o is ArrayList)
            o := ArrayList(o)
        for i in o.arr
        {
            contains_flag := false
            for j in this.arr
            {
                try
                {
                    Java.Assert.assertEquals(i, j)
                    contains_flag := true
                    break
                }
                catch
                    continue
            }
            if !contains_flag
                return false
        }
        return true
    }
    
    get(index)
    {
        return this.arr[index + 1]
    }
    
    isEmpty()
    {
        return this.arr.length == 0
    }
    
    toahk()
    {
        return monoExtra.deepAhkType(this.arr)
    }
    
    toArray(a := [])
    {
        for i in this.arr
            a.push(i)
        return a
    }
    
    toString()
    {
        if this.arr.length < 1
            return "[]"
        plus := ""
        text := "[" . monoExtra.toString(this.arr[1])
        loop this.arr.length - 1
            plus .= "," . monoExtra.toString(this.arr[a_index + 1])
        text .= plus
        text .= "]"
        return text
    }
    
    size()
    {
        return this.arr.length
    }
}

class AssertionError extends Error
{
    
}

class AtomicInteger
{
    __new(initialValue := 0)
    {
        this.value := initialValue
    }
    
    get()
    {
        return this.value
    }
    
    set(newValue)
    {
        this.value := newValue
    }
    
    incrementAndGet()
    {
        return ++this.value
    }
    
    decrementAndGet()
    {
        return --this.value
    }
    
    addAndGet(delta)
    {
        return (this.value += delta)
    }
}

class Boolean
{
    static FALSE := Boolean(false)
    
    static TRUE := Boolean(true)
    
    __new(flag)
    {
        this.flag := flag is Boolean ? flag.flag : !!flag
    }
    
    toahk()
    {
        return this.flag
    }
    
    toString()
    {
        return this.flag ? "true" : "false"
    }
}

class Character
{
    static isDigit(str)
    {
        return isdigit(str)
    }
    
    static isWhitespace(str)
    {
        return isspace(str)
    }
}

class ConcurrentModificationException extends Error
{
    
}

class Date
{
    __new(_date := Java.Null())
    {
        this.date := _date is Date ? _date.date : _date
    }
    
    toahk()
    {
        return strreplace(this.date, "+0000", "Z")
    }
    
    toString()
    {
        return strreplace(this.date, "+0000", "Z")
    }
}

class FileNotFoundException extends RuntimeException
{
    
}

class HashMap extends Map
{
    contains(o)
    {
        if o is string
            return this.has(o)
        return false
    }
    
    containsEntry(key, value)
    {
        flag := this.has(key)
        if !flag
            return false
        try
        {
            Java.Assert.assertEquals(this[key], value)
            return true
        }
        return false
    }
    
    containsKey(var1)
    {
        return this.has(var1)
    }
    
    entrySet()
    {
        return HashMap.Entry(this)
    }
    
    get(var1)
    {
        return this.has(var1) ? this[var1] : Java.Null()
    }
    
    isEmpty()
    {
        return this.count == 0
    }
    
    keySet()
    {
        keyArray := ArrayList()
        for key, value in this
            keyArray.add(key)
        return keyArray
    }
    
    put(var1, var2)
    {
        ret := Java.Null()
        if this.has(var1)
            ret := this[var1]
        this[var1] := var2
        return ret
    }
    
    size()
    {
        return this.count
    }
    
    toahk()
    {
        ahk_map := map()
        for key, value in this
            ahk_map[key] := monoExtra.deepAhkType(value)
        return ahk_map
    }
    
    tomap()
    {
        ahk_map := map()
        for key, value in this
            ahk_map[key] := value
        return ahk_map
    }
    
    valueSet()
    {
        valueArray := ArrayList()
        for key, value in this
            valueArray.add(value)
        return valueArray
    }
    
    class Entry
    {
        __new(_hashmap)
        {
            this.enum := [_hashmap.__enum()]
            this.hashmap := _hashmap
            this.key := Java.Null()
            this.value := Java.Null()
            this.keyArray := ArrayList()
            this.valueArray := ArrayList()
            for key, value in _hashmap
            {
                this.keyArray.add(key)
                this.valueArray.add(value)
            }
        }
        
        __enum(_ := 1)
        {
            return fn
            
            fn(&entry)
            {
                entry := this.next(&enumFlag := true)
                return enumFlag
            }
        }
        
        getKey()
        {
            return this.key
        }
        
        getValue()
        {
            return this.value
        }
        
        iterator()
        {
            this.enum := [this.hashmap.__enum()]
            return this
        }
        
        next(&enumFlag := true)
        {
            if !this.enum[1](&key, &value)
            {
                key := Java.Null()
                value := Java.Null()
                enumFlag := false
            }
            this.key := key
            this.value := value
            return this
        }
        
        keySet()
        {
            return this.keyArray
        }
        
        tohashmap()
        {
            return this.hashmap.clone()
        }
        
        tomap()
        {
            return this.hashmap.tomap()
        }
        
        valueSet()
        {
            return this.valueArray
        }
    }
}

class Java
{
    static file(filename)
    {
        if !filename
            return false
        if fileexist(filename)
            return filename
        else if fileexist(format("{}\lib\{}", regread("HKLM\SOFTWARE\AutoHotkey", "InstallDir", ""), filename))
            return format("{}\lib\{}", regread("HKLM\SOFTWARE\AutoHotkey", "InstallDir", ""), filename)
        else if fileexist(format("{}\lib\{}", a_scriptdir, filename))
            return format("{}\lib\{}", a_scriptdir, filename)
        else
            return false
    }
    
    static fileopen(filename, mode := "r", encoding := "utf-8")
    {
        if !Java.file(filename)
            throw FileNotFoundException("The system cannot find the file specified.")
        else
            return fileopen(filename, mode, encoding)
    }
    
    static getResourceAsStream(lib, filename, mode := "r", encoding := "utf-8")
    {
        return fileopen(Java.file(format("{}\resources\{}", lib, filename)), mode, encoding)
    }
    
    class Assert
    {
        static assertEquals(expected, actual)
        {
            if expected.hasmethod("toahk")
                expected := expected.toahk()
            else if expected is number
                expected := expected is float ? round(expected, 15) : string(expected)
            if actual.hasmethod("toahk")
                actual := actual.toahk()
            else if actual is number
                actual := actual is float ? round(actual, 15) : string(actual)
            first_cmp := expected = actual
            if !first_cmp
            {
                if type(expected) != type(actual)
                    throw AssertionError(format("Type {} cannot compare with Type {}.", type(expected), type(actual)))
                else if expected is string
                    throw AssertionError(format("{} and {} do not match.", expected, actual))
                else if expected is array
                {
                    second_cmp := true
                    if expected.length != actual.length
                        second_cmp := false
                    else
                    {
                        enum1 := expected.__enum()
                        enum2 := actual.__enum()
                        loop expected.length
                        {
                            enum1(&var1)
                            enum2(&var2)
                            try
                                Java.Assert.assertEquals(var1, var2)
                            catch
                            {
                                second_cmp := false
                                break
                            }
                        }
                    }
                    if !second_cmp
                        throw AssertionError("input arrays do not match.")
                }
                else if expected is map
                {
                    second_cmp := true
                    if expected.count != actual.count
                        second_cmp := false
                    else
                    {
                        enum1 := expected.__enum()
                        enum2 := actual.__enum()
                        loop expected.count
                        {
                            enum1(&key1, &value1)
                            enum2(&key2, &value2)
                            try
                            {
                                Java.Assert.assertEquals(key1, key2)
                                Java.Assert.assertEquals(value1, value2)
                            }
                            catch
                            {
                                second_cmp := false
                                break
                            }
                        }
                    }
                    if !second_cmp
                        throw AssertionError("input maps do not match.")
                }
                else if expected.hasmethod("ownprops")
                {
                    second_cmp := true
                    enum1 := expected.ownprops()
                    enum2 := actual.ownprops()
                    while enum1(&name1, &value1)
                    {
                        enum2(&name2, &value2)
                        try
                        {
                            Java.Assert.assertEquals(name1, name2)
                            Java.Assert.assertEquals(value1, value2)
                        }
                        catch
                        {
                            second_cmp := false
                            break
                        }
                    }
                    if !second_cmp
                        throw AssertionError("input objects do not match.")
                }
                else
                        throw AssertionError("input living examples cannot be compared.")
            }
        }
        
        static assertFalse(bool)
        {
            if !(bool is Boolean)
                bool := Boolean(bool)
            try
                Java.Assert.assertEquals(bool, Boolean(false))
            catch
                throw AssertionError("input is true.")
        }
        
        static assertNotNull(object)
        {
            if (object is Java.Null)
                throw AssertionError(format("expected not null, but got null"))
        }
        
        static assertNull(object)
        {
            if !(object is Java.Null)
                throw AssertionError(format("expected null, but was: Type {}.", type(object)))
        }
        
        static assertThat(actual, _matcher)
        {
            if _matcher.name == "contains"
            {
                if _matcher.hasprop("special")
                {
                    special := _matcher.special
                    if special == "instanceOf"
                    {
                        for arg in actual.arr
                            Java.Assert.assertThat(arg, Matchers.instanceOf(_matcher.args[a_index].class))
                    }
                }
                else
                {
                    if actual.hasmethod("contains")
                    {
                        if !(actual.contains(_matcher.args))
                            throw AssertionError("input do not contains.")
                    }
                    else
                        throw AssertionError(format("Type {} has no method contains", type(actual)))
                }
            }
            else if _matcher.name == "empty"
            {
                if actual.hasmethod("isempty")
                {
                    if !(actual.isempty())
                        throw AssertionError("input is not empty.")
                }
                else
                    throw AssertionError(format("Type {} has no method empty", type(actual)))
            }
            else if _matcher.name == "endsWith"
            {
                if actual.hasmethod("toString") || actual is number || actual is string
                {
                    if substr(actual, -strlen(_matcher.str)) != _matcher.str
                        throw AssertionError(format("input is not endsWith {}.", _matcher.str))
                }
                else
                    throw AssertionError(format("Type {} has no method toString", type(actual)))
            }
            else if _matcher.name == "entry"
            {
                if actual.hasmethod("containsEntry")
                {
                    if !(actual.containsEntry(_matcher.key, _matcher.value))
                        throw AssertionError("input do not contains this entry.")
                }
                else
                    throw AssertionError(format("Type {} has no method containsEntry", type(actual)))
            }
            else if _matcher.name == "equal"
                Java.Assert.assertEquals(actual, _matcher.obj)
            else if _matcher.name == "instanceOf"
            {
                if !(actual is _matcher.class)
                    throw AssertionError(format("Expected: class {}, but got: class {}", _matcher.class.__class, type(actual)))
            }
            else if _matcher.name == "size"
            {
                if actual.hasmethod("size")
                {
                    if (_matcher.size != actual.size())
                        throw AssertionError(format("Expected: size {}, but got: size {}", _matcher.size, actual.size()))
                }
                else
                    throw AssertionError(format("Type {} has no method size", type(actual)))
            }
            else if _matcher.name == "startsWith"
            {
                if actual.hasmethod("toString") || actual is number || actual is string
                {
                    if substr(actual, 1, strlen(_matcher.str)) != _matcher.str
                        throw AssertionError(format("input is not startsWith {}.", _matcher.str))
                }
                else
                    throw AssertionError(format("Type {} has no method toString", type(actual)))
            }
        }
        
        static assertTrue(bool)
        {
            if !(bool is Boolean)
                bool := Boolean(bool)
            try
                Java.Assert.assertEquals(bool, Boolean(true))
            catch
                throw AssertionError("input is false.")
        }
        
        static fail(message := "")
        {
            if !message
                throw AssertionError("")
            else
                throw AssertionError(message)
        }
    }
    
    class Null
    {
        
    }
}

class IllegalArgumentException extends Error
{
    
}

class IllegalStateException extends Error
{
    
}

class Matcher
{
    __new(outer, input)
    {
        this.outer := outer
        this.input := input
        this.regex := Java.Null()
        this._start := 0
        this._end := 0
        this.name := ""
    }
    
    find()
    {
        if !(this.regex is Java.Null)
            this._start += this.regex.pos + this.regex.len - 1
        flag := !regexmatch(this.input, this.outer.regex, &regex)
        this.regex := regex
        if !flag
        {
            group_count := this.regex.count
            this.input := substr(this.input, this.regex.pos[group_count] + this.regex.len[group_count])
            this._end += this.regex.pos + this.regex.len - 1
        }
        return !flag
    }
    
    group(num := 0)
    {
        if !num
            return this.regex[]
        return this.regex[num]
    }
    
    groupcount()
    {
        return this.regex.count
    }
    
    matches()
    {
        return this.find()
    }
    
    start()
    {
        return this._start
    }
    
    end()
    {
        return this._end
    }
}

class Matchers
{
    static contains(args*)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "contains"
        _matcher.args := args
        if args.length && args[1] is Matcher
            _matcher.special := "instanceOf"
        return _matcher
    }
    
    static empty()
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "empty"
        return _matcher
    }
    
    static endsWith(str)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "endsWith"
        _matcher.str := str
        return _matcher
    }
    
    static equalTo(obj)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "equal"
        _matcher.obj := obj
        return _matcher
    }
    
    static hasEntry(key, value)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "entry"
        _matcher.key := key
        _matcher.value := value
        return _matcher
    }
    
    static hasSize(size)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "size"
        _matcher.size := size
        return _matcher
    }
    
    static instanceOf(_class)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "instanceOf"
        _matcher.class := _class
        return _matcher
    }
    
    static startsWith(str)
    {
        _matcher := Matcher(Java.Null(), Java.Null())
        _matcher.name := "startsWith"
        _matcher.str := str
        return _matcher
    }
}

class NoSuchElementException extends Error
{
    
}

class Pattern
{
    __new(regex)
    {
        this.regex := regex
    }
    
    static compile(regex)
    {
        return Pattern(regex)
    }
    
    matcher(input)
    {
        return Matcher(this, input)
    }
}

class Reader
{
    
}

class RuntimeException extends Error
{
    
}

class StringBuilder
{
    __new(capacity := 16)
    {
        if capacity is string
            this.capacity := strlen(capacity)
        else
            this.capacity := capacity
        this.str := ""
    }
    
    append(str)
    {
        if str is StringBuilder
            this.str .= str.str
        else
            this.str .= str
        return this
    }
    
    insert(offset, str)
    {
        tmpstr1 := substr(this.str, 1, offset)
        tmpstr2 := substr(this.str,  offset + 1)
        this.str := tmpstr1 str tmpstr2
        return this
    }
    
    length()
    {
        return strlen(this.str)
    }
    
    toString()
    {
        return this.str
    }
}

class StringWriter extends Writer
{
    __new()
    {
        this.str := ""
    }
    
    write(str)
    {
        this.str .= str
    }
    
    toString()
    {
        return this.str
    }
}

class TimeZone
{
    __new(ID := "GMT")
    {
        this.ID := ID
    }
    
    static getTimeZone(ID)
    {
        _timeZone := TimeZone(ID)
        return _timeZone
    }
}

class Writer
{
    
}

class monoExtra
{
    static UNICODE_REGEX := Pattern.compile("\\[uU](.{4})")
    
    static arrayToMap(arr)
    {
        if arr is map
            return arr
        else if !(arr is array)
            return map()
        ahk_map := map()
        for arr_value in arr
        {
            if arr_value is map
            {
                for key, value in arr_value
                {
                    if ahk_map.has(key)
                    {
                        if value is array
                        {
                            tmp_map := monoExtra.arrayToMap(value)
                            if tmp_map.count
                                value := tmp_map
                        }
                        if ahk_map[key] is array
                            ahk_map[key].push(value)
                        else
                            ahk_map[key] := [ahk_map[key], value]
                    }
                    else
                        ahk_map[key] := value
                }
            }
        }
        return ahk_map
    }
    
    static castMapClass(mmap, targetClass, replaceMap := map(), mapFlag := false, protoFlag := true)
    {
        if !mapFlag
            mmap := monoExtra.deepAhkType(mmap)
        for key, value in mmap
        {
            tmp_map := monoExtra.arrayToMap(value)
            if tmp_map.count
                mmap[key] := tmp_map
        }
        for key, value in mmap
        {
            if value is map
            {
                tmp := monoExtra.registerSubClass(key, targetClass, , protoFlag)
                monoExtra.castMapClass(value, tmp, replaceMap, true, protoFlag)
            }
            else
            {
                tmp_object := protoFlag ? targetClass.prototype : targetClass
                if tmp_object.hasprop(key)
                {
                    if tmp_object.%key% is array
                        tmp_object.%key%.push(value)
                    else
                        tmp_object.%key% := [tmp_object.%key%, value]
                }
                else
                    tmp_object.%key% := value
            }
        }
        return targetClass
    }
    
    static deepAhkType(obj)
    {
        if obj.hasmethod("toahk")
            return obj.toahk()
        else if obj is array
        {
            ahk_array := []
            for value in obj
                ahk_array.push(monoExtra.deepAhkType(value))
            return ahk_array
        }
        else if obj is map
        {
            ahk_map := map()
            for key, value in obj
                ahk_map[key] := monoExtra.deepAhkType(value)
            return ahk_map
        }
        return obj
    }
    
    static exchangeSpecialCharacters(s)
    {
        s := strreplace(s, "\", "\\")
        return s
    }
    
    static getClass(str)
    {
        try
        {
            str := (str is string || str is array) ? str : str is func ? str.name : str is class ? str.Prototype.__class : str.__class
            lst_str := str is array ? str : strsplit(str, ".")
            if !lst_str.length
                return class
            base_class := %lst_str[1]%
            loop lst_str.length - 1
                base_class := base_class.%lst_str[a_index + 1]%
        }
        catch error as err
            return
        return base_class
    }
    
    static getSimpleName(obj)
    {
        return strsplit(obj.__class, ".")[-1]
    }
    
    static isAssignableFrom(obj1, obj2)
    {
        class1 := obj1 is class ? obj1 : monoExtra.getClass(obj1.__class)
        return obj2 is class1
    }
    
    static isNestedMap(mmap)
    {
        mmap_flag := false
        for key, value in mmap
        {
            if (value is map)
            {
                mmap_flag := true
                break
            }
        }
        return mmap_flag
    }
    
    static registerClass(classname, funcMap := map(), protoFlag := true)
    {
        defProp := {}.defineprop
        tmp_class := class()
        tmp_class.Prototype := {__Class: classname}
        tmp_class.base := object
        for funcName, funcValue in funcMap
        {
            if protoFlag
                tmp_class.Prototype.%funcName% := funcValue
            else
                tmp_class.%funcName% := funcValue
        }
        defProp(tmp_class, "call", {call: registerClassCall})
        defProp(registerClassCall, "IsBuiltIn", {get: (self) => true})
        
        registerClassCall(self, param*)
        {
            return {base: self.Prototype}
        }
        
        return tmp_class
    }

    static registerSubClass(classname, baseClass, funcMap := map(), protoFlag := true)
    {
        defProp := {}.defineprop
        defProp(registerClassCall, "IsBuiltIn", {get: (self) => true})
        if !(baseClass.hasprop(classname) && (baseClass.%classname% is class))
        {
            tmp_class := class()
            tmp_class.Prototype := {__Class: baseClass.Prototype.__class "." classname}
            tmp_class.base := object
            for funcName, funcValue in funcMap
            {
                if protoFlag
                    tmp_class.Prototype.%funcName% := funcValue
                else
                    tmp_class.%funcName% := funcValue
            }
            defProp(tmp_class, "call", {call: registerClassCall})
            tmp_class.call()
        }
        else
        {
            tmp_class := baseClass.%classname%
            for funcName, funcValue in funcMap
            {
                if protoFlag
                    tmp_class.Prototype.%funcName% := funcValue
                else
                    tmp_class.%funcName% := funcValue
            }
        }
        baseClass.%classname% := tmp_class
        
        registerClassCall(self, param*)
        {
            return {base: self.Prototype}
        }
        
        return tmp_class
    }
    
    static replaceUnicodeCharacters(value)
    {
        unicodeMatcher := monoExtra.UNICODE_REGEX.matcher(value)
        while (unicodeMatcher.find())
            value := strreplace(value, unicodeMatcher.group(), chr(integer("0x" unicodeMatcher.group(1))))
        return value
    }
    
    static replaceSpecialCharacters(s)
    {
        i := 0
        while (i < strlen(s) - 1)
        {
            ch := substr(s, i + 1, 1)
            next := substr(s, i + 2, 1)
            if (ch == '\' && next == '\')
                i++
            else if (ch == '\' && !(next == 'b' || next == 'f' || next == 'n' || next == 't' || next == 'r' || next == '"' || next == '\'))
                return Java.Null()
            i++
        }
        s := strreplace(s, "\n", "`n")
        s := strreplace(s, '\"', '"')
        s := strreplace(s, "\t", "`t")
        s := strreplace(s, "\r", "`r")
        s := strreplace(s, "\\", "\")
        s := strreplace(s, "\/", "/")
        s := strreplace(s, "\b", "`b")
        s := strreplace(s, "\f", "`f")
        return s
    }
    
    static toString(obj)
    {
        if obj.hasmethod("toString")
            return obj.toString()
        else if obj is number || obj is string
            return obj
        return format("{type: {}}", type(obj))
    }
}
