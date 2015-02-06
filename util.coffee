_.extend J,
    assert: (boolValue, errorMessage) ->
        unless boolValue
            if errorMessage
                throw new Meteor.Error "Assertion failed: #{errorMessage}"
            else
                throw new Meteor.Error "Assertion failed."

J.util =
    compare: (a, b) ->
        ###
            All this function does is:
            1. undefined < null < anything else
            2. compare arrays using lexicographic ordering
            3. reject weird cases like comparing plain objects
        ###

        if arguments.length isnt 2
            throw 'Compare needs 2 arguments'

        if a is undefined or b is undefined
            if a is undefined and b is undefined then 0
            else if a is undefined then -1
            else 1

        else if a is null or b is null
            if a is null and b is null then 0
            else if a is null then -1
            else 1

        else if _.isArray(a) or _.isArray(b)
            unless _.isArray(a) and _.isArray(b)
                throw 'Can\'t compare array with non-array'

            lastResult = 0
            i = 0
            while lastResult is 0 and i < Math.max a.length, b.length
                # If one of the arrays is shorter/longer,
                # we use compare(something, undefined) semantics
                lastResult = J.util.compare a[i], b[i]
                i += 1

            lastResult

        else
            aKey = J.util.sortKeyFunc(a)
            bKey = J.util.sortKeyFunc(b)
            if aKey < bKey then -1
            else if aKey > bKey then 1
            else 0

    concatArrays: (arrays...) ->
        _.reduce arrays, (memo, arr) -> memo.concat arr

    containsId: (objOrIdArr, objOrId) ->
        J.util.flattenId(objOrId) in J.util.flattenIds objOrIdArr

    equals: (a, b) ->
        # Go one level deep into arrays because some reactive expressions
        # seem to make good use of this.

        if a is b
            true
        else if _.isArray(a) and _.isArray(b) and a.length is b.length
            _.all (a[i] is b[i] for i in [0...a.length])
        else
            false

    deepEquals: (a, b) ->
        if a is b
            true

        else if _.isArray(a) and _.isArray(b)
            a.length is b.length and _.all (
                J.util.deepEquals(a[i], b[i]) for i in [0...a.length]
            )

        else if J.util.isPlainObject(a) and J.util.isPlainObject(b) and
            J.util.equals(_.keys(a).sort(), _.keys(b).sort()) and _.all(
                J.util.equals(a[k], b[k]) for k of a
            )

        else
            false

    filter: (list, predicate = _.identity, context) ->
        _.filter list, predicate, context

    flattenId: (objOrId) ->
        if objOrId instanceof J.Model
            objOrId._id
        else
            objOrId

    flattenIds: (objOrIdArr) ->
        J.util.flattenId objOrId for objOrId in objOrIdArr

    fractionToColor: (fraction, saturation = 100, luminosity = 50) ->
        if typeof fraction is 'number' and not isNaN fraction
            "hsl(#{120 * fraction}, #{saturation}%, #{luminosity}%)"
        else if isNaN(fraction) or not fraction?
            '#999'
        else
            throw 'Invalid fraction: #{fraction}'

    getField: (obj, fieldSpec) ->
        ###
            >>> getFieldSpec({a: {b: {c: 5}, d: 6}}, 'a?.b.c')
            5

            >>> getFieldSpec({a: {b: {c: 5}, d: 6}}, 'a.x?.c')
            undefined

            >>> getFieldSpec({a: {b: {c: 5}, d: 6}}, 'a.x.c')
            <error>
        ###

        # 'a?.b.c' -> ['a', '?', 'b', '', 'c']
        fieldSpecParts = fieldSpec.split /(\??)\./
        numFieldSpecParts = fieldSpecParts.length // 2 + 1

        value = obj
        for i in [0...numFieldSpecParts]
            questionMark = i > 0 and fieldSpecParts[i * 2 - 1] is '?'
            nextKey = fieldSpecParts[i * 2]

            if questionMark and not value?
                return

            if J.Model? and value instanceof J.Model
                unless _.isFunction value[nextKey]
                    throw new Meteor.Error "Invalid fieldSpec part #{value.modelClass.name}.#{nextKey} (from #{fieldSpec})"
                value = value[nextKey]()
            else
                value = value[nextKey]

        value

    getUrlWithExtraParams: (url, extraParams) ->
        ###
            >>> getUrlWithExtraParams("http://test.com/abc/def", {key1: "value1", key2: 5});
            "http://test.com/abc/def?key1=value1&key2=5"

            >>> getUrlWithExtraParams("http://test.com/ghi?x=7&y=2&", {key1: "value1", x: 3});
            "http://test.com/ghi?x=3&y=2&key1=value1"
        ###

        unless _.isString url
            throw new Meteor.Error "URL must be a string: #{url}"

        uri = URI url
        uri.setQuery extraParams
        uri.href()

    invalidateAtTime: (ms) ->
        # TODO: ms can be a Date in the future too
        dep = new Deps.Dependency()
        dep.depend()
        Meteor.setTimeout(
            => dep.changed()
            ms
        )

    isPlainObject: (obj) ->
        ### Based on $.isPlainObject ###
        return false unless obj?
        return false if typeof obj isnt 'object'
        return false if obj is obj.window
        return false if obj.nodeType
        return false if obj.constructor and not ({}).hasOwnProperty.call(obj.constructor.prototype, 'isPrototypeOf')
        return false if obj._isReactElement
        true

    makeDictSet: (arr) ->
        dictSet = {}
        for x in arr
            dictSet[x] = true
        dictSet

    makeParamString: (params) ->
        uri = URI ''
        (uri.setQuery(key, value) if value?) for key, value of params
        uri.href().substring(1)

    matchesUrlPattern: (url, urlPattern) ->
        uri = URI url
        dummyUri = URI uri
        pUri = URI urlPattern
        dummyPUri = URI pUri

        # Make sure the path before the "?" are equal.
        return false unless URI(uri).query("").equals URI(pUri).query("")

        for paramName, valuePattern of pUri.query(true)
            if valuePattern?[0] is '{' and valuePattern[-1..] is '}'
                regexPattern = '^(' + valuePattern[1...-1] + ')$'
                regex = new RegExp regexPattern, 'i'
                if regex.test(uri.query(true)[paramName] or '')
                    # Replace the regex with a copy of the literal value it matched
                    # to help make the dummy check true at the end
                    urlParamValue = uri.query(true)[paramName]
                    if urlParamValue
                        dummyPUri.setQuery paramName, urlParamValue
                    else
                        dummyPUri.removeQuery paramName
                else
                    return false
            else if not valuePattern
                dummyPUri.removeQuery paramName

        for paramName, value of uri.query(true)
            unless value
                dummyUri.removeQuery paramName

        dummyUri.equals dummyPUri

    moveCursorToEnd: (textInputDomNode) ->
        # This hack works
        textInputDomNode.value = textInputDomNode.value

    setField: (obj, fieldSpec, value) ->
        if fieldSpec.indexOf('?') >= 0
            throw 'No question marks allowed in setter fieldSpecs'

        fieldSpecParts = fieldSpec.split '.'
        if fieldSpecParts.length > 1
            obj = J.util.getField obj, fieldSpecParts[0...-1].join('.')

        obj[fieldSpecParts[fieldSpecParts.length - 1]] = value

    sortByKey: (arr, keySpec = J.util.sortKeyFunc) ->
        keyFunc =
            if _.isString keySpec
                (x) -> J.util.getField x, keySpec
            else if _.isFunction keySpec
                keySpec
            else
                throw new Meteor.Error "Invalid keySpec: #{keySpec}"

        arr.sort (a, b) -> J.util.compare keyFunc(a), keyFunc(b)

    sortKeyFunc: (x) ->
        if _.isString(x)
            x.toUpperCase()
        else if _.isNumber(x)
            x
        else if _.isBoolean(x)
            if x then 1 else 0
        else if typeof x is 'object' and 'key' of x
            J.util.getField x, 'key'
        else
            throw new Meteor.Error "No default sort-key semantics for: #{x}"

    sortByKeyReverse: (arr, keySpec = J.util.sortByKeyFunc) ->
        J.util.sortByKey arr, keySpec
        arr.reverse()

    stringify: (obj) ->
        if obj is undefined
            'undefined'
        else if (
            _.isString(obj) or _.isNumber(obj) or _.isBoolean(obj) or
            obj is null
        )
            JSON.stringify obj
        else if _.isArray(obj)
            "[#{(J.util.stringify x for x in obj).join(", ")}]"
        else if J.util.isPlainObject(obj)
            "{#{("#{J.util.stringify k}:#{J.util.stringify v}" for k, v of obj).join ', '}}"
        else
            obj.toString()



J.utilTests =
    sorting: ->
        J.assert J.util.compare(
            [false, -2]
            [1, -5, 6]
        ) is -1
        J.assert J.util.compare(
            [1, 2, 3, 'test', 5]
            [1, 2.0, 3, 'TeSt', 5.0]
        ) is 0
        J.assert J.util.compare(
            {key: 6}
            5
        ) is 1
        J.assert J.util.deepEquals(
            ['G', 'f'].sort(J.util.compare)
            ['f', 'G']
        )

    matchesUrlPattern: ->
        J.assert J.util.matchesUrlPattern(
            "func://yelp.com/search?cflt=restaurants&find_desc=chicken+wings&attrs=GoodForKids&find_loc=Mountain+View%2Cca&sortby=&open_time=",
            "func://yelp.com/search?cflt=restaurants&find_desc=chicken+wings&attrs=GoodForKids&find_loc=Mountain+View%2Cca&sortby=&open_time="
        )
        J.assert J.util.matchesUrlPattern(
            'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
            'func://yelp.com/search?q=best+restaurants&loc={mountain+view,ca|}'
        )
        J.assert J.util.matchesUrlPattern(
            'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
            'func://yelp.com/search?q=best+restaurants&loc={mountain\+view,ca|}'
        )
        J.assert not J.util.matchesUrlPattern(
            'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
            'func://yelp.com/search?cflt=pizza&q=best+restaurants&loc={mountain+view,ca|}'
        )
        J.assert J.util.matchesUrlPattern(
            'func://www.yellowpages.com/friendly-md/chicken-wings-restaurants?&refinements=',
            'func://www.yellowpages.com/friendly-md/chicken-wings-restaurants?&refinements={a||b}'
        )

for funcName, testFunc of J.utilTests
    testFunc()