###
    TODO: Add a @observe() and @observeChanges() just like
    Meteor's collection API. Good for List and AutoList.
###


class J.List
    constructor: (arr = [], equalsFunc = J.util.equals) ->
        unless @ instanceof J.List
            return new J.List arr, equalsFunc

        if arr instanceof J.List
            arr = arr.getValues()

        unless _.isArray arr
            throw new Meteor.Error "Not an array: #{arr}"

        @equalsFunc = equalsFunc

        fields = {}
        for x, i in arr
            fields[i] = x

        @readOnly = false

        @_dict = J.Dict fields

    _resize: (size) ->
        @_dict.replaceKeys ("#{i}" for i in [0...size])

    clear: ->
        @resize 0

    clone: ->
        # Nonreactive because a clone's fields are their
        # own new piece of application state
        @constructor Tracker.nonreactive => @getValues()

    contains: (value) ->
        # Reactive.
        # The current implementation invalidates somewhat
        # too much.
        # We could make the reactivity more efficient by
        # using a special hashSet of @_containsDeps
        # (one per value argument), but it would be
        # tricky to handle calls to @contains(v)
        # when v isn't J.Dict.encodeKey-able.
        value in @getValues()

    deepEquals: (x) ->
        # Reactive
        return false unless x instanceof @constructor
        J.util.deepEquals @toArr(), x.toArr()

    extend: (values) ->
        valuesArr =
            if values instanceof J.List
                values.getValues()
            else values

        adder = {}
        for value, i in valuesArr
            adder["#{@size() + i}"] = value
        @_dict.setOrAdd adder

    find: (f = _.identity) ->
        # Reactive
        _.find @getValues(), f

    filter: (f = _.identity) ->
        # Reactive
        J.List _.filter @getValues(), f

    forEach: (f) ->
        # Reactive
        # Like map but returns an array
        f value, i for value, i in @getValues()

    get: (index) ->
        # Reactive
        unless _.isNumber(index)
            throw new Meteor.Error "Index must be a number"
        try
            @_dict.forceGet "#{index}"
        catch
            throw new Meteor.Error "List index out of range"

    getConcat: (lst) ->
        # Reactive
        if Tracker.active
            J.AutoList(
                => @size() + lst.size()
                (i) =>
                    if i < @size()
                        @get i
                    else
                        lst.get i - @size()
            )
        else
            J.List @getValues().concat lst.getValues()

    getReversed: ->
        # Reactive
        @map (value, i) => @get @size() - 1 - i

    getSorted: (keySpec = J.util.sortKeyFunc) ->
        # Reactive
        J.List J.util.sortByKey @getValues(), keySpec

    getValues: ->
        # Reactive
        @_dict.get "#{i}" for i in [0...@size()]

    join: (separator) ->
        # Reactive
        @getValues().join separator

    map: (mapFunc) ->
        # Reactive
        if Tracker.active
            J.AutoList(
                => @size()
                (i) => mapFunc @get(i), i
            )
        else
            J.List @getValues().map mapFunc

    push: (value) ->
        @extend [value]

    resize: (size) ->
        @_resize size

    reverse: ->
        reversedArr = Tracker.nonreactive => @getReversed().toArr()
        @set i, reversedArr[i] for i in [0...reversedArr.length]
        null

    set: (index, value) ->
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"
        unless _.isNumber(index) and @_dict.hasKey "#{index}"
            throw new Meteor.Error "List index out of range"

        setter = {}
        setter[index] = value
        @_dict.set setter

    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @_dict.setReadOnly @readOnly, deep

    sort: (keySpec = J.util.sortKeyFunc) ->
        sortedArr = Tracker.nonreactive => @getSorted(keySpec).toArr()
        @set i, sortedArr[i] for i in [0...sortedArr.length]
        null

    size: ->
        # Reactive
        @_dict.size()

    toArr: ->
        # Reactive
        values = @getValues()

        arr = []
        for value, i in values
            if value instanceof J.Dict
                arr.push value.toObj()
            else if value instanceof J.List
                arr.push value.toArr()
            else
                arr.push value
        arr

    toString: ->
        "List#{J.util.stringify @getValues()}"

    tryGet: (index) ->
        # Reactive
        if @_dict.hasKey "#{index}"
            @get index
        else
            undefined

    @fromDeepArr: (arr) ->
        unless _.isArray arr
            throw new Meteor.Error "Expected an array"

        J.Dict.fromDeepObjOrArr arr