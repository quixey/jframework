class J.List
    constructor: (arr = [], equalsFunc = J.util.equals) ->
        unless @ instanceof J.List
            return new J.List arr, equalsFunc

        unless _.isArray arr
            throw new Meteor.Error "Not an array: #{arr}"

        @equalsFunc = equalsFunc

        fields = {}
        for x, i in arr
            fields[i] = x

        @active = true
        @readOnly = false

        @_size = arr.length
        @_sizeDep = new Deps.Dependency()

        @_dict = J.Dict fields

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

    get: (index) ->
        # Reactive
        unless parseInt(index) is index and 0 <= index < @_size
            throw new Meteor.Error "List index out of range"
        @_dict.get index

    getReversed: ->
        # Reactive
        # Fixme: Use a LazyList for the fine-granularity solution
        J.List @toArr().reverse()

    getSorted: (keySpec = J.util.sortKeyFunc) ->
        # Reactive
        # Fixme: Use a LazyList for the fine-granularity solution
        J.List J.util.sortByKey @getValues(), keySpec

    getValues: ->
        # Reactive
        @_sizeDep.depend()
        @_dict.get i for i in [0...@_size]

    join: (separator) ->
        # Reactive
        @getValues().join separator

    map: (mapFunc) ->
        # Reactive

#        ## Fixme: This is the fine-granularity solution
#        J.LazyList(
#            => @size()
#            (i) => mapFunc @get i
#        )

        J.List @getValues().map mapFunc

    push: (value) ->
        adder = {}
        adder[@_size] = value
        @_dict.setOrAdd adder
        @_size += 1
        @_sizeDep.changed()

    resize: (size) ->
        return if size is @_size
        @_dict.replaceKeys [0...size]
        @_size = size
        @_sizeDep.changed()

    reverse: ->
        reversedArr = Tracker.nonreactive => @getReversed().toArr()
        @set i, reversedArr[i] for i in [0...reversedArr.length]
        null

    set: (index, value) ->
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"
        unless parseInt(index) is index and 0 <= index < @_size
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

    stop: ->
        if @active
            @active = false
            @_dict.stop()

    size: ->
        # Reactive
        @_sizeDep.depend()
        @_size

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

    @fromDeepArr: (arr) ->
        unless _.isArray arr
            throw new Meteor.Error "Expected an array"

        J.Dict.fromDeepObjOrArr arr