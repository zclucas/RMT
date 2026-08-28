#Include "TomlBase.ahk"

class ArrayValueReader
{
    static ARRAY_VALUE_READER := ArrayValueReader()
    
    canRead(s)
    {
        return substr(s, 1, 1) == "["
    }
    
    read(s, index, _context)
    {
        line := _context.line
        startLine := line.get()
        startIndex := index.get()
        arrayItems := ArrayList()
        terminated := false
        inComment := false
        errors := Results.Errors()
        i := index.incrementAndGet()
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (c == '#' && !inComment)
                inComment := true
            else if (c == '`n')
            {
                inComment := false
                line.incrementAndGet()
            }
            else if (inComment || Character.isWhitespace(c) || c == ',')
            {
                i := index.incrementAndGet()
                continue
            }
            else if (c == '[')
            {
                converted := this.read(s, index, _context)
                if (converted is Results.Errors)
                    errors.add(converted)
                else if (!this.isHomogenousArray(converted, arrayItems))
                    errors.heterogenous(_context.identifier.getName(), line.get())
                else
                    arrayItems.add(converted)
                i := index.incrementAndGet()
                continue
            }
            else if (c == ']')
            {
                terminated := true
                break
            }
            else
            {
                converted := ValueReaders.VALUE_READERS.convert(s, index, _context)
                if (converted is Results.Errors)
                    errors.add(converted)
                else if (!this.isHomogenousArray(converted, arrayItems))
                    errors.heterogenous(_context.identifier.getName(), line.get())
                else
                    arrayItems.add(converted)
            }
            i := index.incrementAndGet()
        }
        if (!terminated)
            errors.unterminated(_context.identifier.getName(), substr(s, startIndex + 1, strlen(s) - startIndex), startLine)
        if (errors.hasErrors())
            return errors
        return arrayItems
    }
    
    isHomogenousArray(o, values)
    {
        return values.isEmpty() || monoExtra.isAssignableFrom(values.get(0), o) || monoExtra.isAssignableFrom(o, values.get(0))
    }
}

class ArrayValueWriter
{
    isPrimitiveType()
    {
        return false
    }
    
    normalize(value)
    {
        if value is ArrayList
            value := value.arr
        return value
    }
    
    static isArrayish(value)
    {
        return value is array || value is ArrayList
    }
    
    static isArrayOfPrimitive(_array)
    {
        first := ArrayValueWriter.peek(_array)
        if !(first is Java.Null)
        {
            valueWriter := ValueWriters.WRITERS.findWriterFor(first)
            return valueWriter.isPrimitiveType() || ArrayValueWriter.isArrayish(first)
        }
        return true
    }
    
    static peek(value)
    {
        if value is ArrayList
            value := value.arr
        if (value is array)
        {
            if (value.length > 0)
                return value[1]
            else
                return Java.Null()
        }
        return Java.Null()
    }
}

class BooleanValueReaderWriter
{
    static BOOLEAN_VALUE_READER_WRITER := BooleanValueReaderWriter()
    
    canRead(s)
    {
        return substr(s, 1, 4) == "true" || substr(s, 1, 5) == "false"
    }
    
    canWrite(value)
    {
        return value is Boolean
    }
    
    isPrimitiveType()
    {
        return true
    }
    
    read(s, index, _context)
    {
        s := substr(s, index.get() + 1)
        b := substr(s, 1, 4) == "true" ? Boolean(true) : Boolean(false)
        endIndex := b.flag == true ? 4 : 5
        index.addAndGet(endIndex - 1)
        return b
    }
    
    write(value, _context)
    {
        _context.write(value.toString())
    }
}

class Container
{
    class Table extends Container
    {
        __new(tableName := Java.Null(), implicit := false)
        {
            this.values := HashMap()
            this.name := tableName
            this.implicit := implicit
        }
        
        accepts(key)
        {
            return (!this.values.containsKey(key)) || this.values.get(key) is Container.TableArray
        }
        
        put(key, value)
        {
            this.values.put(key, value)
        }
        
        get(key)
        {
            return this.values.get(key)
        }
        
        isImplicit()
        {
            return this.implicit
        }
        
        consume()
        {
            for entrykey, entryvalue in this.values
            {
                if (entryvalue is Container.Table)
                    this.values[entrykey] := entryvalue.consume()
                else if (entryvalue is Container.TableArray)
                    this.values[entrykey] := entryvalue.getValues()
            }
            return this.values
        }
    }
    
    class TableArray extends Container
    {
        __new()
        {
            this.values := ArrayList()
            this.values.add(Container.Table())
        }
        
        accepts(key)
        {
            return this.getCurrent().accepts(key)
        }
        
        put(key, value)
        {
            this.values.add(value)
        }
        
        isImplicit()
        {
            return false
        }
        
        getValues()
        {
            unwrappedValues := ArrayList()
            for table in this.values.arr
                unwrappedValues.add(table.consume())
            return unwrappedValues
        }
        
        getCurrent()
        {
            return this.values.get(this.values.size() - 1)
        }
    }
}

class Context
{
    __new(_identifier := Identifier(), line := AtomicInteger(), errors := Results.Errors())
    {
        this.identifier := _identifier
        this.line := line
        this.errors := errors
    }
    
    with(_identifier)
    {
        return Context(_identifier, this.line, this.errors)
    }
}

class DatePolicy
{
    __new(timeZone, showFractionalSeconds)
    {
        this.timeZone := timeZone
        this.showFractionalSeconds := showFractionalSeconds
    }
    
    getTimeZone()
    {
        return this.timeZone
    }
    
    isShowFractionalSeconds()
    {
        return this.showFractionalSeconds
    }
}

class DateValueReaderWriter
{
    static DATE_VALUE_READER_WRITER := DateValueReaderWriter()
    
    static DATE_REGEX := Pattern.compile("(\d{4}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9])(\.\d*)?(Z|(?:[+\-]\d{2}:\d{2}))(.*)")
    
    canRead(s)
    {
        if (strlen(s) < 5)
            return false
        loop 5
        {
            i := a_index - 1
            c := substr(s, i + 1, 1)
            if (i < 4)
            {
                if (!Character.isDigit(c))
                    return false
            }
            else if (c != '-')
                return false
        }
        return true
    }
    
    canWrite(value)
    {
        return value is Date
    }
    
    isPrimitiveType()
    {
        return true
    }
    
    read(original, index, _context)
    {
        sb := StringBuilder()
        i := index.get()
        while (i < strlen(original))
        {
            c := substr(original, i + 1, 1)
            if (Character.isDigit(c) || c == '-' || c == '+' || c == ':' || c == '.' || c == 'T' || c == 'Z')
                sb.append(c)
            else
            {
                index.decrementAndGet()
                break
            }
            i := index.incrementAndGet()
        }
        s := sb.toString()
        _matcher := DateValueReaderWriter.DATE_REGEX.matcher(s)
        if (!_matcher.matches())
        {
            errors := Results.Errors()
            errors.invalidValue(_context.identifier.getName(), s, _context.line.get())
            return errors
        }
        dateString := _matcher.group(1)
        zone := _matcher.group(3)
        fractionalSeconds := _matcher.group(2)
        _format := "yyyy-MM-dd'T'HH:mm:ss"
        if (fractionalSeconds != "")
        {
            _format .= ".SSS"
            dateString .= fractionalSeconds
        }
        _format .= "Z"
        if (zone == "Z")
            dateString .= "+0000"
        else if (instr(zone, ":"))
        dateString .= strreplace(zone, ":", "")
        try
        {
            /* !!!
            SimpleDateFormat dateFormat = new SimpleDateFormat(format);
            dateFormat.setLenient(false);
            return dateFormat.parse(dateString);
            */
            return Date(dateString)
        }
        catch
        {
            errors := Results.Errors()
            errors.invalidValue(_context.identifier.getName(), s, _context.line.get())
            return errors
        }
    }
    
    write(value, _context)
    {
        /* !!!
        DateFormat formatter = getFormatter(context.getDatePolicy());
        context.write(formatter.format(value));
        */
        _context.write(value.date)
    }
}

class Identifier
{
    static INVALID := Identifier("", Java.Null())
    
    static ALLOWED_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890_-"
    
    static Type := {KEY: 0, TABLE: 1, TABLE_ARRAY: 2}
    
    __new(name := Java.Null(), type := Java.Null())
    {
        this.name := name
        this.type := type
    }
    
    getBareName()
    {
        if this.isKey()
            return this.name
        if this.isTable()
            return substr(this.name, 2, strlen(this.name) - 2)
        return substr(this.name, 3, strlen(this.name) - 4)
    }
    
    getName()
    {
        return this.name
    }
    
    isKey()
    {
        return this.type == Identifier.Type.KEY
    }
    
    isTable()
    {
        return this.type == Identifier.Type.TABLE
    }
    
    isTableArray()
    {
        return this.type == Identifier.Type.TABLE_ARRAY
    }
    
    static extractName(raw)
    {
        quoted := false
        sb := StringBuilder()
        loop strlen(raw)
        {
            i := a_index - 1
            c := substr(raw, a_index, 1)
            if (c == '"' && (i == 0 || substr(raw, i, 1) != '\'))
            {
                quoted := !quoted
                sb.append('"')
            }
            else if (quoted || !Character.isWhitespace(c))
                sb.append(c)
        }
        return StringValueReaderWriter.STRING_VALUE_READER_WRITER.replaceUnicodeCharacters(sb.toString())
    }
    
    static from(name, _context)
    {
        if _context is Java.Null
            _context := Context()
        name := trim(name)
        if substr(name, 1, 2) == "[["
        {
            _type := Identifier.Type.TABLE_ARRAY
            valid := Identifier.isValidTableArray(name, _context)
        }
        else if substr(name, 1, 1) == "["
        {
            _type := Identifier.Type.TABLE
            valid := Identifier.isValidTable(name, _context)
        }
        else
        {
            _type := Identifier.Type.KEY
            valid := Identifier.isValidKey(name, _context)
        }
        if (!valid)
            return Identifier.INVALID
        return Identifier(Identifier.extractName(name), _type)
    }
    
    static isValidKey(name, _context)
    {
        if (!trim(name))
        {
            _context.errors.invalidKey(name, _context.line.get())
            return false
        }
        quoted := false
        loop strlen(name)
        {
            i := a_index - 1
            c := substr(name, a_index, 1)
            if (c == '"' && (i == 0 || substr(name, i, 1) != '\'))
            {
                if (!quoted && i > 0 && substr(name, i, 1) != '.')
                {
                    _context.errors.invalidKey(name, _context.line.get())
                    return false
                }
                quoted := !quoted
            }
            else if (!quoted && (!instr(Identifier.ALLOWED_CHARS, c)))
            {
                _context.errors.invalidKey(name, _context.line.get())
                return false
            }
        }
        return true
    }
    
    static isValidTable(name, _context)
    {
        valid := true
        if substr(name, -1) != "]"
            valid := false
        trimmed := trim(substr(name, 2, strlen(name) - 2))
        if !trimmed || substr(trimmed, 1, 1) == '.' || substr(trimmed, -1) == "."
            valid := false
        if (!valid)
        {
            _context.errors.invalidTableArray(name, _context.line.get())
            return false
        }
        quoted := false
        dotAllowed := false
        quoteAllowed := true
        charAllowed := true
        loop strlen(trimmed)
        {
            i := a_index - 1
            c := substr(trimmed, a_index, 1)
            if (!valid)
                break
            if Keys.isQuote(c)
            {
                if (!quoteAllowed)
                    valid := false
                else if (quoted && substr(trimmed, i, 1) != '\')
                {
                    charAllowed := false
                    dotAllowed := true
                    quoteAllowed := false
                }
                else if (!quoted)
                {
                    quoted := true
                    quoteAllowed := true
                }
            }
            else if quoted
                continue
            else if (c == '.')
            {
                if (dotAllowed)
                {
                    charAllowed := true
                    dotAllowed := false
                    quoteAllowed := true
                }
                else
                {
                    _context.errors.emptyImplicitTable(name, _context.line.get())
                    return false
                }
            }
            else if (Character.isWhitespace(c))
            {
                prev := substr(trimmed, i, 1)
                if (!Character.isWhitespace(prev) && prev != '.')
                {
                    charAllowed := false
                    dotAllowed := true
                    quoteAllowed := true
                }
            }
            else
            {
                if (charAllowed && instr(Identifier.ALLOWED_CHARS, c) > 0)
                {
                    charAllowed := true
                    dotAllowed := true
                    quoteAllowed := false
                }
                else
                    valid := false
            }
        }
        if (!valid)
        {
            _context.errors.invalidTable(name, _context.line.get())
            return false
        }
        return true
    }
    
    static isValidTableArray(line, _context)
    {
        valid := true
        if substr(line, -2) != "]]"
            valid := false
        trimmed := trim(substr(line, 3, strlen(line) - 4))
        if !trimmed || substr(trimmed, 1, 1) == '.' || substr(trimmed, -1) == "."
            valid := false
        if (!valid)
        {
            _context.errors.invalidTableArray(line, _context.line.get())
            return false
        }
        quoted := false
        dotAllowed := false
        quoteAllowed := true
        charAllowed := true
        loop strlen(trimmed)
        {
            i := a_index - 1
            c := substr(trimmed, a_index, 1)
            if (!valid)
                break
            if (c == '"')
            {
                if (!quoteAllowed)
                    valid := false
                else if (quoted && substr(trimmed, i, 1) != '\')
                {
                    charAllowed := false
                    dotAllowed := true
                    quoteAllowed := false
                }
                else if (!quoted)
                {
                    quoted := true
                    quoteAllowed := true
                }
            }
            else if quoted
                continue
            else if (c == '.')
            {
                if (dotAllowed)
                {
                    charAllowed := true
                    dotAllowed := false
                    quoteAllowed := true
                }
                else
                {
                    _context.errors.emptyImplicitTable(line, _context.line.get())
                    return false
                }
            }
            else if (Character.isWhitespace(c))
            {
                prev := substr(trimmed, i, 1)
                if (!Character.isWhitespace(prev) && prev != '.' && prev != '"')
                {
                    charAllowed := false
                    dotAllowed := true
                    quoteAllowed := true
                }
            }
            else
            {
                if (charAllowed && instr(Identifier.ALLOWED_CHARS, c) > 0)
                {
                    charAllowed := true
                    dotAllowed := true
                    quoteAllowed := false
                }
                else
                    valid := false
            }
        }
        if (!valid)
        {
            _context.errors.invalidTableArray(line, _context.line.get())
            return false
        }
        return true
    }
}

class IdentifierConverter
{
    static IDENTIFIER_CONVERTER := IdentifierConverter()
    
    convert(s, index, _context)
    {
        quoted := false
        name := StringBuilder()
        terminated := false
        isKey := substr(s, index.get() + 1, 1) != '['
        isTableArray := !isKey && strlen(s) > index.get() + 1 && substr(s, index.get() + 2, 1) == '['
        inComment := false
        i := index.get()
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (Keys.isQuote(c) && (i == 0 || substr(s, i, 1) != '\'))
            {
                quoted := !quoted
                name.append(c)
            }
            else if (c == '`n')
            {
                index.decrementAndGet()
                break
            }
            else if quoted
                name.append(c)
            else if (c == '=' && isKey)
            {
                terminated := true
                break
            }
            else if (c == ']' && !isKey)
            {
                if (!isTableArray || strlen(s) > index.get() + 1 && substr(s, index.get() + 2, 1) == ']')
                {
                    terminated := true
                    name.append(']')
                    if (isTableArray)
                        name.append(']')
                }
            }
            else if (terminated && c == '#')
                inComment := true
            else if (terminated && !Character.isWhitespace(c) && !inComment)
            {
                terminated := false
                break
            }
            else if (!terminated)
                name.append(c)
            i := index.incrementAndGet()
        }
        if (!terminated)
        {
            if isKey
                _context.errors.unterminatedKey(name.toString(), _context.line.get())
            else
                _context.errors.invalidKey(name.toString(), _context.line.get())
            return Identifier.INVALID
        }
        return Identifier.from(name.toString(), _context)
    }
}

class IndentationPolicy
{
    __new(keyIndentation, tableIndentation, arrayDelimiterPadding)
    {
        this.keyValueIndent := keyIndentation
        this.tableIndent := tableIndentation
        this.arrayDelimiterPadding := arrayDelimiterPadding
    }
    
    getTableIndent()
    {
        return this.tableIndent
    }
    
    getKeyValueIndent()
    {
        return this.keyValueIndent
    }
    
    getArrayDelimiterPadding()
    {
        return this.arrayDelimiterPadding
    }
}

class InlineTableValueReader
{
    static INLINE_TABLE_VALUE_READER := InlineTableValueReader()
    
    canRead(s)
    {
        return substr(s, 1, 1) == "{"
    }
    
    read(s, sharedIndex, _context)
    {
        line := _context.line
        startLine := line.get()
        startIndex := sharedIndex.get()
        inKey := true
        inValue := false
        terminated := false
        currentKey := StringBuilder()
        _results := HashMap()
        errors := Results.Errors()
        i := sharedIndex.incrementAndGet()
        while (sharedIndex.get() < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (inValue && !Character.isWhitespace(c))
            {
                converted := ValueReaders.VALUE_READERS.convert(s, sharedIndex, _context.with(Identifier.from(currentKey.toString(), _context)))
                if (converted is Results.Errors)
                {
                    errors.add(converted)
                    return errors
                }
                currentKeyTrimmed := trim(currentKey.toString())
                previous := _results.put(currentKeyTrimmed, converted)
                if (!(previous is Java.Null))
                {
                    errors.duplicateKey(currentKeyTrimmed, _context.line.get())
                    return errors
                }
                currentKey := StringBuilder()
                inValue := false
            }
            else if (c == ',')
            {
                inKey := true
                inValue := false
                currentKey := StringBuilder()
            }
            else if (c == '=')
            {
                inKey := false
                inValue := true
            }
            else if (c == '}')
            {
                terminated := true
                break
            }
            else if (inKey)
                currentKey.append(c)
            i := sharedIndex.incrementAndGet()
        }
        if (!terminated)
        errors.unterminated(_context.identifier.getName(), substr(s, startIndex + 1), startLine)
        if (errors.hasErrors())
            return errors
        return _results
    }
}

class Keys
{
    static isQuote(c)
    {
        return c == '"' || c == "'"
    }
    
    static split(key)
    {
        splitKey := ArrayList()
        current := StringBuilder()
        quoted := false
        indexable := true
        inIndex := false
        index := -1
        key_length := strlen(key)
        loop key_length
        {
            i := key_length - a_index
            c := substr(key, i + 1, 1)
            if (c == ']' && indexable)
            {
                inIndex := true
                continue
            }
            indexable := false
            if (c == '[' && inIndex)
            {
                inIndex := false
                index := integer(current.toString())
                current := StringBuilder()
                continue
            }
            if (Keys.isQuote(c) && (i == 0 || substr(key, i, 1) != '\'))
            {
                quoted := !quoted
                indexable := false
            }
            if (c != '.' || quoted)
                current.insert(0, c)
            else
            {
                splitKey.add(0, Keys.Key(current.toString(), index, !splitKey.isEmpty() ? splitKey.get(0) : Java.Null()))
                indexable := true
                index := -1
                current := StringBuilder()
            }
        }
        splitKey.add(0, Keys.Key(current.toString(), index, !splitKey.isEmpty() ? splitKey.get(0) : Java.Null()))
        return splitKey.toArray([])
    }
    
    class Key
    {
        __new(name, index, next := Java.Null())
        {
            this.name := name
            this.index := index
            if (!(next is Java.Null))
                this.path := name "." next.path
            else
                this.path := name
        }
    }
}

class LiteralStringValueReader
{
    static LITERAL_STRING_VALUE_READER := LiteralStringValueReader()
    
    canRead(s)
    {
        return substr(s, 1, 1) == "'"
    }
    
    read(s, index, _context)
    {
        startLine := _context.line.get()
        terminated := false
        startIndex := index.incrementAndGet()
        i := index.get()
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (c == "'")
            {
                terminated := true
                break
            }
            i := index.incrementAndGet()
        }
        if (!terminated)
        {
            errors := Results.Errors()
            errors.unterminated(_context.identifier.getName(), substr(s, startIndex + 1), startLine)
            return errors
        }
        substring := substr(s, startIndex + 1, index.get() - startIndex)
        return substring
    }
}

class MapValueWriter
{
    static MAP_VALUE_WRITER := MapValueWriter()
    
    static REQUIRED_QUOTING_PATTERN := Pattern.compile("^.*[^A-Za-z\d_-].*$")
    
    canWrite(value)
    {
        return value is map
    }
    
    isPrimitiveType()
    {
        return false
    }
    
    write(value, _context)
    {
        from := value
        if (MapValueWriter.hasPrimitiveValues(from, _context))
            _context.writeKey()
        ; Render primitive types and arrays of primitive first so they are
        ; grouped under the same table (if there is one)
        for key, fromValue in from
        {
            if (fromValue is Java.Null)
                continue
            valueWriter := ValueWriters.WRITERS.findWriterFor(fromValue)
            if (valueWriter.isPrimitiveType())
            {
                _context.indent()
                _context.write(MapValueWriter.quoteKey(key)).write(" = ")
                valueWriter.write(fromValue, _context)
                _context.write('`n')
            }
            else if (valueWriter == PrimitiveArrayValueWriter.PRIMITIVE_ARRAY_VALUE_WRITER)
            {
                _context.indent()
                _context.setArrayKey(key)
                _context.write(MapValueWriter.quoteKey(key)).write(" = ")
                valueWriter.write(fromValue, _context)
                _context.write('`n')
            }
        }
        ; Now render (sub)tables and arrays of tables
        for key, fromValue in from
        {
            if (fromValue is Java.Null)
                continue
            valueWriter := ValueWriters.WRITERS.findWriterFor(fromValue)
            if (valueWriter == this || valueWriter == ObjectValueWriter.OBJECT_VALUE_WRITER || valueWriter == TableArrayValueWriter.TABLE_ARRAY_VALUE_WRITER)
                valueWriter.write(fromValue, _context.pushTable(MapValueWriter.quoteKey(key)))
        }
    }
    
    static hasPrimitiveValues(values, _context)
    {
        for fromValue in values
        {
            if fromValue is Java.Null
                continue
            valueWriter := ValueWriters.WRITERS.findWriterFor(fromValue)
            if (valueWriter.isPrimitiveType() || valueWriter == PrimitiveArrayValueWriter.PRIMITIVE_ARRAY_VALUE_WRITER)
                return true
        }
        return false
    }
    
    static quoteKey(key)
    {
        stringKey := key
        _matcher := MapValueWriter.REQUIRED_QUOTING_PATTERN.matcher(stringKey)
        if (_matcher.matches())
            stringKey := '"' stringKey '"'
        return stringKey
    }
}

class MultilineLiteralStringValueReader
{
    static MULTILINE_LITERAL_STRING_VALUE_READER := MultilineLiteralStringValueReader()
    
    canRead(s)
    {
        return substr(s, 1, 3) == "'''"
    }
    
    read(s, index, _context)
    {
        line := _context.line
        startLine := line.get()
        originalStartIndex := index.get()
        startIndex := index.addAndGet(3)
        endIndex := -1
        if (substr(s, startIndex + 1, 1) == '`n')
        {
            startIndex := index.incrementAndGet()
            line.incrementAndGet()
        }
        i := startIndex
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (c == '`n')
                line.incrementAndGet()
            if (c == "'" && strlen(s) > i + 2 && substr(s, i + 2, 1) == "'" && substr(s, i + 3, 1) == "'")
            {
                endIndex := i
                index.addAndGet(2)
                break
            }
            i := index.incrementAndGet()
        }
        if (endIndex == -1)
        {
            errors := Results.Errors()
            errors.unterminated(_context.identifier.getName(), substr(s, originalStartIndex + 1), startLine)
            return errors
        }
        return substr(s, startIndex + 1, endIndex - startIndex)
    }
}

class MultilineStringValueReader
{
    static MULTILINE_STRING_VALUE_READER := MultilineStringValueReader()
    
    canRead(s)
    {
        return substr(s, 1, 3) == '"""'
    }
    
    read(s, index, _context)
    {
        line := _context.line
        startLine := line.get()
        originalStartIndex := index.get()
        startIndex := index.addAndGet(3)
        endIndex := -1
        if (substr(s, startIndex + 1, 1) == '`n')
        {
            startIndex := index.incrementAndGet()
            line.incrementAndGet()
        }
        i := startIndex
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            if (c == '`n')
                line.incrementAndGet()
            else if (c == '"' && strlen(s) > i + 2 && substr(s, i + 2, 1) == '"' && substr(s, i + 3, 1) == '"')
            {
                endIndex := i
                index.addAndGet(2)
                break
            }
            i := index.incrementAndGet()
        }
        if (endIndex == -1)
        {
            errors := Results.Errors()
            errors.unterminated(_context.identifier.getName(), substr(s, originalStartIndex + 1), startLine)
            return errors
        }
        s := substr(s, startIndex + 1, endIndex - startIndex)
        s := regexreplace(s, "\\\s+", "")
        s := StringValueReaderWriter.STRING_VALUE_READER_WRITER.replaceUnicodeCharacters(s)
        s := StringValueReaderWriter.STRING_VALUE_READER_WRITER.replaceSpecialCharacters(s)
        return s
    }
}

class NumberValueReaderWriter
{
    static NUMBER_VALUE_READER_WRITER := NumberValueReaderWriter()
    
    canRead(s)
    {
        firstChar := substr(s, 1, 1)
        return firstChar == '+' || firstChar == '-' || Character.isDigit(firstChar)
    }
    
    canWrite(value)
    {
        return value is number
    }
    
    isPrimitiveType()
    {
        return true
    }

    read(s, index, _context)
    {
        signable := true
        dottable := false
        exponentable := false
        terminatable := false
        underscorable := false
        _type := ""
        sb := StringBuilder()
        i := index.get()
        while (i < strlen(s))
        {
            c := substr(s, i + 1, 1)
            notLastChar := strlen(s) > i + 1
            if (Character.isDigit(c))
            {
                sb.append(c)
                signable := false
                terminatable := true
                if (!_type)
                {
                    _type := "integer"
                    dottable := true
                }
                underscorable := notLastChar
                exponentable := !(_type == "exponent")
            }
            else if ((c == '+' || c == '-') && signable && notLastChar)
            {
                signable := false
                terminatable := false
                if (c == '-')
                    sb.append('-')
            }
            else if (c == '.' && dottable && notLastChar)
            {
                sb.append('.')
                _type := "float"
                terminatable := false
                dottable := false
                exponentable := false
                underscorable := false
            }
            else if ((c == 'E' || c == 'e') && exponentable && notLastChar)
            {
                sb.append('E')
                _type := "exponent"
                terminatable := false
                signable := true
                dottable := false
                exponentable := false
                underscorable := false
            }
            else if (c == '_' && underscorable && notLastChar && Character.isDigit(substr(s, i + 2, 1)))
                underscorable := false
            else
            {
                if (!terminatable)
                    _type := ""
                index.decrementAndGet()
                break
            }
            i := index.incrementAndGet()
        }
        if (_type == "integer")
            return integer(sb.toString())
        else if (_type == "float")
            return float(sb.toString())
        else if (_type == "exponent")
            return float(sb.toString())
        else
        {
            errors := Results.Errors()
            errors.invalidValue(_context.identifier.getName(), sb.toString(), _context.line.get())
            return errors
        }
    }
    
    write(value, _context)
    {
        _context.write(value)
    }
}

class ObjectValueWriter
{
    static OBJECT_VALUE_WRITER := ObjectValueWriter()
    
    canWrite(value)
    {
        return true
    }
    
    isPrimitiveType()
    {
        return false
    }
    
    write(value, _context)
    {
        to := map()
        fields := value
        if !(type(fields) = "Prototype")
        {
            for fieldname, fieldvalue in fields.ownprops()
                to[fieldname] := fieldvalue
        }
        MapValueWriter.MAP_VALUE_WRITER.write(to, _context)
    }
}

class PrimitiveArrayValueWriter extends ArrayValueWriter
{
    static PRIMITIVE_ARRAY_VALUE_WRITER := PrimitiveArrayValueWriter()
    
    canWrite(value)
    {
        return ArrayValueWriter.isArrayish(value) && ArrayValueWriter.isArrayOfPrimitive(value)
    }
    
    write(o, _context)
    {
        values := this.normalize(o)
        _context.write('[')
        _context.writeArrayDelimiterPadding()
        first := true
        firstWriter := Java.Null()
        for value in values
        {
            if first
            {
                firstWriter := ValueWriters.WRITERS.findWriterFor(value)
                first := false
            }
            else
            {
                _writer := ValueWriters.WRITERS.findWriterFor(value)
                if (_writer != firstWriter)
                {
                    throw IllegalStateException(_context.getContextPath() ": cannot write a heterogeneous array; first element was of type " type(firstWriter) " but found " type(_writer))
                }
                _context.write(", ")
            }
            ValueWriters.WRITERS.findWriterFor(value).write(value, _context)
        }
        _context.writeArrayDelimiterPadding()
        _context.write(']')
    }
}

class Results
{
    __new()
    {
        this.errors := Results.Errors()
        this.stack := ArrayDeque()
        this.stack.push(Container.Table(""))
    }
    
    addValue(key, value, line)
    {
        currentTable := this.stack.peek()
        if value is map
        {
            path := this.getInlineTablePath(key)
            if path is Java.Null
                this.startTable(key, line)
            else if !path
                this.startTables(Identifier.from(key, Java.Null()), line)
            else
                this.startTables(Identifier.from(path, Java.Null()), line)
            valueMap := value
            for entrykey, entryvalue in valueMap
                this.addValue(entrykey, entryvalue, line)
            this.stack.pop()
        }
        else if (currentTable.accepts(key))
            currentTable.put(key, value)
        else
        {
            if (currentTable.get(key) is Container)
                this.errors.keyDuplicatesTable(key, line)
            else
                this.errors.duplicateKey(key, !(line is Java.Null) ? line.get() : -1)
        }
    }
    
    consume()
    {
        values := this.stack.getLast()
        this.stack.clear()
        return values.consume()
    }
    
    getInlineTablePath(key)
    {
        descendingIterator := this.stack.descendingIterator()
        sb := StringBuilder()
        while (descendingIterator.hasNext())
        {
            next := descendingIterator.next()
            if (next is Container.TableArray)
                return Java.Null()
            table := next
            if table.name is Java.Null
                break
            if sb.length() > 0
                sb.append('.')
            sb.append(table.name)
        }
        if sb.length() > 0
            sb.append('.')

        sb.append(key)
            .insert(0, '[')
            .append(']')

        return sb.toString()
    }
    
    startTable(args*)
    {
        if args.length == 2
        {
            tableName := args[1]
            line := args[2]
            newTable := Container.Table(tableName)
            this.addValue(tableName, newTable, line)
            this.stack.push(newTable)
            return newTable
        }
        else if args.length == 3
        {
            tableName := args[1]
            implicit := args[2]
            line := args[3]
            newTable := Container.Table(tableName, implicit)
            this.addValue(tableName, newTable, line)
            this.stack.push(newTable)
            return newTable
        }
    }
    
    startTables(id, line)
    {
        tableName := id.getBareName()
        while (this.stack.size() > 1)
            this.stack.pop()
        tableParts := Keys.split(tableName)
        loop tableParts.length
        {
            i := a_index - 1
            tablePart := tableParts[i + 1].name
            currentContainer := this.stack.peek()
            if (currentContainer.get(tablePart) is Container)
            {
                nextTable := currentContainer.get(tablePart)
                if (i == tableParts.length - 1 && !nextTable.isImplicit())
                {
                    this.errors.duplicateTable(tableName, line.get())
                    return
                }
                this.stack.push(nextTable)
                if (this.stack.peek() is Container.TableArray)
                    this.stack.push(this.stack.peek().getCurrent())
            }
            else if (currentContainer.accepts(tablePart))
                this.startTable(tablePart, i < tableParts.length - 1, line)
            else
            {
                this.errors.tableDuplicatesKey(tablePart, line)
                break
            }
        }
    }
    
    startTableArray(_identifier, line)
    {
        tableName := _identifier.getBareName()
        while (this.stack.size() > 1)
            this.stack.pop()
        tableParts := Keys.split(tableName)
        loop tableParts.length
        {
            i := a_index - 1
            tablePart := tableParts[i + 1].name
            currentContainer := this.stack.peek()
            if (currentContainer.get(tablePart) is Container.TableArray)
            {
                currentTableArray := currentContainer.get(tablePart)
                this.stack.push(currentTableArray)
                if (i == tableParts.length - 1)
                    currentTableArray.put(tablePart, Container.Table())
                this.stack.push(currentTableArray.getCurrent())
                currentContainer := this.stack.peek()
            }
            else if (currentContainer.get(tablePart) is Container.Table && i < tableParts.length - 1)
            {
                nextTable := currentContainer.get(tablePart)
                this.stack.push(nextTable)
            }
            else if (currentContainer.accepts(tablePart))
            {
                newContainer := i == tableParts.length - 1 ? Container.TableArray() : Container.Table()
                this.addValue(tablePart, newContainer, line)
                this.stack.push(newContainer)
                if (newContainer is Container.TableArray)
                    this.stack.push(newContainer.getCurrent())
            }
            else
            {
                this.errors.duplicateTable(tableName, line.get())
                break
            }
        }
    }
    
    class Errors
    {
        sb := StringBuilder()
        
        duplicateTable(table, line)
        {
            this.sb.append("Duplicate table definition on line ")
                      .append(line)
                      .append(": [")
                      .append(table)
                      .append("]")
        }
        
        tableDuplicatesKey(table, line)
        {
            this.sb.append("Key already exists for table defined on line ")
                      .append(line.get())
                      .append(": [")
                      .append(table)
                      .append("]")
        }
        
        keyDuplicatesTable(key, line)
        {
            this.sb.append("Table already exists for key defined on line ")
                      .append(line.get())
                      .append(": ")
                      .append(key)
        }
        
        emptyImplicitTable(table, line)
        {
            this.sb.append("Invalid table definition due to empty implicit table name: ")
                      .append(table)
        }
        
        invalidTable(table, line)
        {
            this.sb.append("Invalid table definition on line ")
                      .append(line)
                      .append(": ")
                      .append(table)
        }
        
        duplicateKey(key, line)
        {
            this.sb.append("Duplicate key")
            if line > -1
            {
                this.sb.append(" on line ")
                          .append(line)
            }
            this.sb.append(": ")
                      .append(key)
        }
        
        invalidTextAfterIdentifier(_identifier, text, line)
        {
            this.sb.append("Invalid text after key ")
                      .append(_identifier.getName())
                      .append(" on line ")
                      .append(line)
                      .append(". Make sure to terminate the value or add a comment (#).")
        }
        
        invalidKey(key, line)
        {
            this.sb.append("Invalid key on line ")
                      .append(line)
                      .append(": ")
                      .append(key)
        }
        
        invalidTableArray(tableArray, line)
        {
            this.sb.append("Invalid table array definition on line ")
                      .append(line)
                      .append(": ")
                      .append(tableArray)
        }
        
        invalidValue(key, value, line)
        {
            this.sb.append("Invalid value on line ")
                      .append(line)
                      .append(": ")
                      .append(key)
                      .append(" = ")
                      .append(value)
        }
        
        unterminatedKey(key, line)
        {
            this.sb.append("Key is not followed by an equals sign on line ")
                      .append(line)
                      .append(": ")
                      .append(key)
        }
        
        unterminated(key, value, line)
        {
            this.sb.append("Unterminated value on line ")
                      .append(line)
                      .append(": ")
                      .append(key)
                      .append(" = ")
                      .append(trim(value))
        }
        
        heterogenous(key, line)
        {
            this.sb.append(key)
                      .append(" becomes a heterogeneous array on line ")
                      .append(line)
        }
        
        hasErrors()
        {
            return this.sb.length() > 0
        }
        
        toString()
        {
            return this.sb.toString()
        }
        
        add(other)
        {
            this.sb.append(other.sb)
        }
    }
}

class StringValueReaderWriter
{
    static STRING_VALUE_READER_WRITER := StringValueReaderWriter()
    
    static UNICODE_REGEX := Pattern.compile("\\[uU](.{4})")
    
    static specialCharacterEscapes := map('`b', "\b", '`t', "\t", '`n', "\n", '`f', "\f", '`r', "\r", '"', "\`"", '\', "\\")
    
    canRead(s)
    {
        return substr(s, 1, 1) == '"'
    }
    
    canWrite(value)
    {
        return value is string
    }
    
    escapeUnicode(_in, _context)
    {
        loop strlen(_in)
        {
            i := a_index - 1
            codePoint := substr(_in, i + 1, 1)
            if (ord(codePoint) < 93 && StringValueReaderWriter.specialCharacterEscapes.has(codePoint))
                _context.write(StringValueReaderWriter.specialCharacterEscapes[codePoint])
            else
                _context.write(codePoint)
        }
    }
    
    isPrimitiveType()
    {
        return true
    }

    read(s, index, _context)
    {
        startIndex := index.incrementAndGet()
        endIndex := -1
        i := index.get()
        while (i < strlen(s))
        {
            ch := substr(s, i + 1, 1)
            if (ch == '"' && substr(s, i, 1) != '\')
            {
                endIndex := i
                break
            }
            i := index.incrementAndGet()
        }
        if (endIndex == -1)
        {
            errors := Results.Errors()
            errors.unterminated(_context.identifier.getName(), substr(s, startIndex), _context.line.get())
            return errors
        }
        raw := substr(s, startIndex + 1, endIndex - startIndex)
        s := this.replaceUnicodeCharacters(raw)
        s := this.replaceSpecialCharacters(s)
        if (s is Java.Null)
        {
            errors := Results.Errors()
            errors.invalidValue(_context.identifier.getName(), raw, _context.line.get())
            return errors
        }
        return s
    }
    
    replaceUnicodeCharacters(value)
    {
        unicodeMatcher := StringValueReaderWriter.UNICODE_REGEX.matcher(value)
        while (unicodeMatcher.find())
            value := strreplace(value, unicodeMatcher.group(), chr(integer("0x" unicodeMatcher.group(1))))
        return value
    }
    
    replaceSpecialCharacters(s)
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
    
    write(value, _context)
    {
        _context.write('"')
        value := this.replaceUnicodeCharacters(value)
        this.escapeUnicode(value, _context)
        _context.write('"')
    }
}

class TableArrayValueWriter extends ArrayValueWriter
{
    static TABLE_ARRAY_VALUE_WRITER := TableArrayValueWriter()
    
    canWrite(value)
    {
        return ArrayValueWriter.isArrayish(value) && !ArrayValueWriter.isArrayOfPrimitive(value)
    }
    
    write(from, _context)
    {
        values := this.normalize(from)
        subContext := _context.pushTableFromArray()
        for value in values
            ValueWriters.WRITERS.findWriterFor(value).write(value, subContext)
    }
}

class Toml
{
    
    __new(defaults := Java.Null(), values := HashMap())
    {
        this.defaults := defaults
        this.values := values
    }
    
    contains(key)
    {
        return !(this.get(key) is Java.Null)
    }
    
    containsEntry(key, value)
    {
        flag := this.contains(key)
        if !flag
            return false
        try
        {
            Java.Assert.assertEquals(this.get(key), value)
            return true
        }
        return false
    }
    
    containsPrimitive(key)
    {
        _object := this.get(key)
        return !(this.get(key) is Java.Null) && !(_object is map) && !(_object is ArrayList)
    }
    
    containsTable(key)
    {
        _object := this.get(key)
        return !(this.get(key) is Java.Null) && (_object is map)
    }
    
    containsTableArray(key)
    {
        _object := this.get(key)
        return !(this.get(key) is Java.Null) && (_object is ArrayList)
    }
    
    entrySet()
    {
        return Toml.Entry(this)
    }
    
    get(key)
    {
        if (this.values.containsKey(key))
            return this.values.get(key)
        current := this.values
        _keys := Keys.split(key)
        for k in _keys
        {
            if (k.index == -1 && current is Map && current.containsKey(k.path))
                return current.get(k.path)
            current := current.get(k.name)
            if (k.index > -1 && !(current is Java.Null))
            {
                if (k.index >= current.size())
                    return Java.Null()
                current := current.get(k.index)
            }
            if (current is Java.Null)
                return !(this.defaults is Java.Null) ? this.defaults.get(key) : Java.Null()
        }
        return current
    }
    
    getBoolean(key, defaultValue := Java.Null())
    {
        bool := this.get(key)
        if bool is Boolean
            return bool
        return defaultValue
    }
    
    getDate(key, defaultValue := Java.Null())
    {
        _date := this.get(key)
        if _date is Date
            return _date
        return defaultValue
    }
    
    getDouble(key, defaultValue := Java.Null())
    {
        double := this.get(key)
        if double is float
            return double
        return defaultValue
    }
    
    getEntry(key)
    {
        value := this.get(key)
        
    }
    
    getFloat(key, defaultValue := Java.Null())
    {
        double := this.get(key)
        if double is float
            return double
        return defaultValue
    }
    
    getInt(key, defaultValue := Java.Null())
    {
        int := this.get(key)
        if int is integer
            return int
        return defaultValue
    }
    
    getList(key, defaultValue := Java.Null())
    {
        list := this.get(key)
        if list is ArrayList
            return list
        return defaultValue
    }
    
    getLong(key, defaultValue := Java.Null())
    {
        int := this.get(key)
        if int is integer
            return int
        return defaultValue
    }
    
    getString(key, defaultValue := Java.Null())
    {
        str := this.get(key)
        if str is string
            return str
        return defaultValue
    }
    
    getTable(key)
    {
        table := this.get(key)
        if table is map
            return Toml(, table)
        return Java.Null()
    }
    
    getTables(key)
    {
        tableArray := this.get(key)
        if tableArray is Java.Null
            return Java.Null()
        tables := ArrayList()
        for table in tableArray.arr
            tables.add(Toml(, table))
        return tables
    }
    
    isEmpty()
    {
        return this.values.isEmpty()
    }
    
    read(tomlString, type := "text", encoding := "utf-8")
    {
        if tomlString is file || tomlString is Reader
            tomlString := tomlString.read()
        else if tomlString is Toml
        {
            this.values := tomlString.values
            return this
        }
        else if type = "file"
            tomlString := fileread(tomlString, encoding)
        _results := TomlParser.run(tomlString)
        if (_results.errors.hasErrors())
            throw IllegalStateException(_results.errors.toString())
        this.values := _results.consume()
        return this
    }
    
    to(targetClass, replaceMap := map(), protoFlag := true)
    {
        if !(this.defaults is Java.Null)
            monoExtra.castMapClass(this.defaults.toahk(), targetClass, replaceMap, , protoFlag)
        castedClass := monoExtra.castMapClass(this.values.toahk(), targetClass, replaceMap, , protoFlag)
        if protoFlag
            return {base: castedClass.prototype}
        return castedClass
    }
    
    toahk()
    {
        return this.values.toahk()
    }
    
    tomap()
    {
        return this.values.tomap()
    }
    
    class Entry extends HashMap.Entry
    {
        __new(_toml)
        {
            this.enum := [_toml.values.__enum()]
            this._toml := _toml
            this.key := Java.Null()
            this.value := Java.Null()
            this.keyArray := ArrayList()
            this.valueArray := ArrayList()
            for key, value in _toml.values
            {
                this.keyArray.add(key)
                if (value is map)
                    this.valueArray.add(_toml.getTable(key))
                else if (value is ArrayList)
                {
                    if (!value.isEmpty() && value.get(0) is map)
                        this.valueArray.add(_toml.getTables(key))
                    else
                        this.valueArray.add(value)
                }
                else
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
        
        iterator()
        {
            this.enum := [this._toml.values.__enum()]
            return this
        }
        
        next(&enumFlag := true)
        {
            if !this.enum[1](&key, &value)
            {
                this.key := Java.Null()
                this.value := Java.Null()
                enumFlag := false
                return this
            }
            this.key := key
            if (value is map)
                this.value := this._toml.getTable(this.key)
            else if (value is ArrayList)
            {
                if (!value.isEmpty() && value.get(0) is map)
                    this.value := this._toml.getTables(this.key)
                else
                    this.value := value
            }
            else
                this.value := value
            return this
        }
        
        tohashmap()
        {
            return this._toml.values.clone()
        }
        
        tomap()
        {
            return this._toml.values.tomap()
        }
    }
}

class TomlParser
{
    static run(tomlString)
    {
        _results := Results()
        if !tomlString
            return _results
        index := AtomicInteger()
        inComment := false
        line := AtomicInteger(1)
        _identifier := Java.Null()
        value := Java.Null()
        i := index.get()
        while (i < strlen(tomlString))
        {
            c := substr(tomlString, i + 1, 1)
            if _results.errors.hasErrors()
                break
            if (c == '#' && !inComment)
                inComment := true
            else if (!Character.isWhitespace(c) && !inComment && _identifier is Java.Null)
            {
                id := IdentifierConverter.IDENTIFIER_CONVERTER.convert(tomlString, index, Context(, line, _results.errors))
                if (id != Identifier.INVALID)
                {
                    if id.isKey()
                        _identifier := id
                    else if id.isTable()
                        _results.startTables(id, line)
                    else if id.isTableArray()
                        _results.startTableArray(id, line)
                }
            }
            else if (c == "`n")
            {
                inComment := false
                _identifier := Java.Null()
                value := Java.Null()
                line.incrementAndGet()
            }
            else if (!inComment && !(_identifier is Java.Null) && _identifier.isKey() && value is Java.Null && !Character.isWhitespace(c))
            {
                value := ValueReaders.VALUE_READERS.convert(tomlString, index, Context(_identifier, line, _results.errors))
                if (value is Results.Errors)
                    _results.errors.add(value)
                else
                    _results.addValue(_identifier.getName(), value, line)
            }
            else if (!(value is Java.Null) && !inComment && !Character.isWhitespace(c))
                _results.errors.invalidTextAfterIdentifier(_identifier, c, line.get())
            i := index.incrementAndGet()
        }
        return _results
    }
}

class TomlWriter
{
    __new(keyIndentation := 0, tableIndentation := 0, arrayDelimiterPadding := 0, _timeZone := TimeZone.getTimeZone("UTC"), showFractionalSeconds := false)
    {
        this.indentationPolicy := IndentationPolicy(keyIndentation, tableIndentation, arrayDelimiterPadding)
        this.datePolicy := DatePolicy(_timeZone, showFractionalSeconds)
    }
    
    write(from, target := StringWriter(), encoding := "utf-8")
    {
        if target is Writer
        {
            valueWriter := ValueWriters.WRITERS.findWriterFor(from)
            if (valueWriter == MapValueWriter.MAP_VALUE_WRITER || valueWriter == ObjectValueWriter.OBJECT_VALUE_WRITER)
            {
                _context := WriterContext(this.indentationPolicy, this.datePolicy, target)
                valueWriter.write(from, _context)
            }
            else
                throw IllegalArgumentException("An object of class " monoExtra.getSimpleName(from) " cannot produce valid TOML. Please pass in a Map or a custom type.")
            return target.toString()
        }
        else if target is file
        {
            output := this.write(from)
            target.write(output)
            return output
        }
        else if target is string
        {
            if substr(target, -5) != ".toml"
                target .= ".toml"
            if !Java.file(target)
                fileappend("", target)
            return this.write(from, fileopen(Java.file(target), "w", encoding))
        }
        else
            throw TypeError("input must be writer, file or filename")
    }
    
    class Builder
    {
        __new()
        {
            this.keyIndentation := 0
            this.tableIndentation := 0
            this.arrayDelimiterPadding := 0
            this._timeZone := TimeZone.getTimeZone("UTC")
            this._showFractionalSeconds := false
        }
        
        indentValuesBy(spaces)
        {
            this.keyIndentation := spaces
            return this
        }
        
        indentTablesBy(spaces)
        {
            this.tableIndentation := spaces
            return this
        }
        
        timeZone(_timeZone)
        {
            this._timeZone := _timeZone
            return this
        }
        
        padArrayDelimitersBy(spaces)
        {
            this.arrayDelimiterPadding := spaces
            return this
        }
        
        build()
        {
            return TomlWriter(this.keyIndentation, this.tableIndentation, this.arrayDelimiterPadding, this.timeZone, this._showFractionalSeconds)
        }
        
        showFractionalSeconds()
        {
            this._showFractionalSeconds := true
            return this
        }
    }
}

class ValueReaders
{
    static READERS := [MultilineStringValueReader.MULTILINE_STRING_VALUE_READER, MultilineLiteralStringValueReader.MULTILINE_LITERAL_STRING_VALUE_READER, LiteralStringValueReader.LITERAL_STRING_VALUE_READER, StringValueReaderWriter.STRING_VALUE_READER_WRITER, DateValueReaderWriter.DATE_VALUE_READER_WRITER, NumberValueReaderWriter.NUMBER_VALUE_READER_WRITER, BooleanValueReaderWriter.BOOLEAN_VALUE_READER_WRITER, ArrayValueReader.ARRAY_VALUE_READER, InlineTableValueReader.INLINE_TABLE_VALUE_READER]
    
    static VALUE_READERS := ValueReaders()
    
    convert(value, index, _context)
    {
        substring := substr(value, index.get() + 1)
        for valueParser in ValueReaders.READERS
        {
            if (valueParser.canRead(substring))
                return valueParser.read(value, index, _context)
        }
        errors := Results.Errors()
        errors.invalidValue(_context.identifier.getName(), substring, _context.line.get())
        return errors
    }
}

class ValueWriters
{
    static WRITERS := ValueWriters()
    
    static VALUE_WRITERS := [StringValueReaderWriter.STRING_VALUE_READER_WRITER, NumberValueReaderWriter.NUMBER_VALUE_READER_WRITER, BooleanValueReaderWriter.BOOLEAN_VALUE_READER_WRITER, ValueWriters.getPlatformSpecificDateConverter(), MapValueWriter.MAP_VALUE_WRITER, PrimitiveArrayValueWriter.PRIMITIVE_ARRAY_VALUE_WRITER, TableArrayValueWriter.TABLE_ARRAY_VALUE_WRITER]
    
    findWriterFor(value)
    {
        for valueWriter in ValueWriters.VALUE_WRITERS
        {
            if (valueWriter.canWrite(value))
                return valueWriter
        }
        return ObjectValueWriter.OBJECT_VALUE_WRITER
    }
    
    static getPlatformSpecificDateConverter()
    {
        return DateValueReaderWriter.DATE_VALUE_READER_WRITER
    }
}

class WriterContext
{
    __new(args*)
    {
        this.arrayKey := Java.Null()
        this.isArrayOfTable := false
        this.empty := true
        if args.length == 3
        {
            key := ""
            tableIndent := ""
            _indentationPolicy := args[1]
            _datePolicy := args[2]
            output := args[3]
        }
        else if args.length
        {
            key := args[1]
            tableIndent := args[2]
            output := args[3]
            _indentationPolicy := args[4]
            _datePolicy := args[5]
        }
        this.key := key
        this.output := output
        this.indentationPolicy := _indentationPolicy
        this.currentTableIndent := tableIndent
        this.datePolicy := _datePolicy
        this.currentFieldIndent := tableIndent this.fillStringWithSpaces(this.indentationPolicy.getKeyValueIndent())
    }
    
    fillStringWithSpaces(count)
    {
        chars := ""
        loop count
            chars .= ' '
        return chars
    }
    
    getContextPath()
    {
        return (!this.key) ? this.arrayKey : this.key "." this.arrayKey
    }
    
    getDatePolicy()
    {
        return this.datePolicy
    }
    
    growIndent(indentationPolicy)
    {
        return this.currentTableIndent this.fillStringWithSpaces(this.indentationPolicy.getTableIndent())
    }
    
    indent()
    {
        if (this.key)
            this.write(this.currentFieldIndent)
    }
    
    pushTable(newKey)
    {
        newIndent := ""
        if this.key
            newIndent := this.growIndent(this.indentationPolicy)
        fullKey := (!this.key) ? newKey : this.key "." newKey
        subContext := WriterContext(fullKey, newIndent, this.output, this.indentationPolicy, this.datePolicy)
        if (!this.empty)
            subContext.empty := false
        return subContext
    }
    
    pushTableFromArray()
    {
        subContext := WriterContext(this.key, this.currentTableIndent, this.output, this.indentationPolicy, this.datePolicy)
        if (!this.empty)
            subContext.empty := false
        subContext.setIsArrayOfTable(true)
        return subContext
    }
    
    setArrayKey(arrayKey)
    {
        this.arrayKey := arrayKey
        return this
    }
    
    setIsArrayOfTable(isArrayOfTable)
    {
        this.isArrayOfTable := isArrayOfTable
        return this
    }
    
    write(s)
    {
        this.output.write(s)
        if (this.empty && s)
            this.empty := false
        return this
    }
    
    writeArrayDelimiterPadding()
    {
        loop this.indentationPolicy.getArrayDelimiterPadding()
            this.write(' ')
    }
    
    writeKey()
    {
        if (!this.key)
            return
        if (!this.empty)
            this.write('`n')
        this.write(this.currentTableIndent)
        if (this.isArrayOfTable)
            this.write("[[").write(this.key).write("]]`n")
        else
            this.write('[').write(this.key).write("]`n")
    }
}
