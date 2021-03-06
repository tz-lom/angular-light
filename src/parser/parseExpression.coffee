
do ->
    toDict = ->
        result = {}
        for k in arguments
            result[k] = true
        result

    reserved = toDict 'instanceof', 'typeof', 'in', 'null', 'true', 'false', 'undefined', 'return'

    isChar = do ->
        rx = /[a-zA-Z\u0410-\u044F\u0401\u0451_\.\$]/
        (x) ->
            x.match rx

    isDigit = (x) ->
        x.charCodeAt() >= 48 and x.charCodeAt() <= 57

    isSign = do ->
        chars = toDict '+', '-', '>', '<', '=', '&', '|', '^', '!', '~'
        (x) ->
            chars[x] or false

    assignmentOperator = toDict '=', '+=', '-=', '++', '--', '|=', '^=', '&=', '!=', '<<=', '>>='

    alight.utils.parsExpression = (expression, option) ->
        option = option or {}
        inputKeywords = toDict.apply null, option.input or []
        uniq = 1
        pars = (option) ->
            line = option.line
            result = option.result or []
            index = option.index or 0
            level = option.level or 0
            stopKey = option.stopKey or null

            variable = ''
            leftVariable = null
            variableChildren = []
            sign = ''
            status = false
            original = ''
            stringKey = ''
            stringValue = ''
            freeText = ''
            bracket = 0
            filters = null

            commitText = ->
                if freeText
                    result.push
                        type: 'free'
                        value: freeText
                freeText = ''

            while index <= line.length
                ap = line[index-1]
                a = line[index++] or ''
                an = line[index]

                if (status and freeText) or (not a)
                    commitText()

                if status is 'string'
                    if a is stringKey and ap isnt '\\'
                        stringValue += a
                        result.push
                            type: 'string'
                            value: stringValue
                        stringValue = ''
                        stringKey = ''
                        status = ''
                        continue
                    stringValue += a
                    continue
                else if status is 'key'
                    if isChar(a) or isDigit(a)
                        variable += a
                        continue
                    if a is '['
                        variable += a
                        child = pars
                            line: line
                            index: index
                            level: level + 1
                            stopKey: ']'

                        if not child.stopKeyOk
                            throw 'Error expression'

                        index = child.index
                        variable += '###' + child.uniq + '###]'
                        variableChildren.push child
                        continue
                    else if a is '?' and (an is '.' or an is '(' or an is '[')  # Elvis
                        variable += a
                        continue
                    else if a is '('  # function
                        variable += a
                        child = pars
                            line: line
                            index: index
                            level: level + 1
                            stopKey: ')'

                        if not child.stopKeyOk
                            throw 'Error expression'

                        index = child.index
                        variable += '###' + child.uniq + '###)'
                        variableChildren.push child
                        continue

                    # new variable
                    leftVariable =
                        type: 'key'
                        value: variable
                        start: index - variable.length - 1
                        finish: index-1
                        children: variableChildren
                    result.push leftVariable
                    status = ''
                    variable = ''
                    variableChildren = []
                else if status is 'sign'
                    if isSign a
                        sign += a
                        continue
                    if sign is '|' and level is 0 and bracket is 0
                        # filters
                        filters = line.substring index-1
                        index = line.length + 1
                        continue

                    if assignmentOperator[sign]
                        leftVariable.assignment = true
                    result.push
                        type: 'sign'
                        value: sign
                    status = ''
                    sign = ''

                # no status
                if isChar a
                    status = 'key'
                    variable += a
                    continue

                if isSign a
                    status = 'sign'
                    sign += a
                    continue

                if a is '"' or a is "'"
                    stringKey = a
                    status = 'string'
                    stringValue += a
                    continue

                if a is stopKey
                    commitText()
                    return {
                        result: result
                        index: index
                        stopKeyOk: true
                        uniq: uniq++
                    }

                if a is '('
                    bracket++
                if a is ')'
                    bracket--
                if a is '{'
                    commitText()
                    child = pars
                        line: line
                        index: index
                        level: level + 1
                        stopKey: '}'
                    result.push
                        type: '{}'
                        child: child
                    index = child.index
                    continue

                if a is ':' and stopKey is '}'
                    leftVariable.type = 'free'

                freeText += a
            commitText()

            result: result
            index: index
            filters: filters

        data = pars
            line: expression

        ret =
            isSimple: not data.filters
            simpleVariables: []
            #filters
            #expression
            #result

        if data.filters
            ret.expression = expression.substring 0, expression.length - data.filters.length - 1
            ret.filters = data.filters.split '|'
        else
            ret.expression = expression

        # build
        splitVariable = (variable) ->
            parts = variable.split(/[\.\[\(\?]/)

            count: parts.length
            firstPart: parts[0]

        toElvis = (name, isReserved) ->
            if isReserved
                '($$=' + name + ',$$==null)?undefined:'
            else
                '($$=$$' + name + ',$$==null)?undefined:'

        getFirstPart = (name) ->
            name.split(/[\.\[\(\?]/)[0]

        convert = (variable) ->
            if variable is 'this'
                return '$$scope'

            firstPart = getFirstPart variable
            isReserved = reserved[firstPart] or inputKeywords[firstPart]

            parts = variable.split '?'
            if parts.length is 1
                if isReserved
                    return variable
                return '$$scope.' + variable

            if isReserved
                result = toElvis parts[0], true
                full = parts[0]
            else
                result = toElvis 'scope.' + parts[0]
                full = 'scope.' + parts[0]
            for p in parts.slice 1, parts.length-1
                if p[0] is '('
                    result += toElvis full + p, isReserved
                else
                    result += toElvis p
                    full += p
            last = parts[parts.length-1]
            if last[0] is '('
                if not isReserved
                    result += '$$'
                result += full + last
            else
                result += '$$' + last

            '(' + result + ')'

        build = (part) ->
            result = ''
            for d in part.result
                if d.type is 'key'
                    if d.assignment
                        sv = splitVariable d.value
                        if sv.firstPart is 'this'
                            name = '$$scope' + d.value.substring 4
                        else if sv.count < 2
                            name = '($$scope.$$root || $$scope).' + d.value
                        else
                            name = '$$scope.' + d.value
                        ret.isSimple = false
                    else
                        if reserved[d.value]
                            name = d.value
                        else
                            name = convert d.value
                            ret.simpleVariables.push name
                    if d.children.length
                        for c in d.children
                            key = "####{c.uniq}###"
                            childName = build c
                            name = name.split(key).join childName
                    result += name
                    continue
                if d.type is '{}'
                    result += '{' + build(d.child) + '}'
                    continue
                result += d.value
            result
        ret.result = build data
        if alight.debug.parser
            console.log expression, ret
        ret
