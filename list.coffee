class J.List
    constructor: (arr = [], @equalsFunc = J.util.equals) ->
        unless _.isArray arr
            throw new Meteor.Error "Not an array: #{arr}"

        fields = {}
        for x, i in arr
            fields[i] = x

        @active = true
        @readOnly = false

        @_size = arr.length
        @_sizeDep = new Deps.Dependency()

        @_dict = new J.Dict fields

    clear: ->
        @resize 0

    get: (index) ->
        # Reactive
        unless 0 <= index < @_size
            throw new Meteor.Error "List index out of range"
        @_dict.get index

    getSortedValues: (keySpec = J.util.sortKeyFunc) ->
        # Reactive
        J.util.sortByKey @getValues(), keySpec

    getValues: ->
        # Reactive
        @_sizeDep.depend()
        @_dict.get i for i in [0...@_size]

    map: (mapFunc) ->
        # Reactive
        @getValues().map mapFunc

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

    set: (index, value) ->
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"
        unless 0 <= index < @_size
            throw new Meteor.Error "List index out of range"

        setter = {}
        setter[index] = value
        @_dict.set setter

    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @_dict.setReadOnly @readOnly, deep

    stop: ->
        if @active
            @active = false
            @_dict.stop()

    size: ->
        # Reactive
        @_sizeDep.depend()
        @_size

    toArr: ->
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
        J.util.toString @toArr()

    @fromDeepArr: (arr) ->
        unless _.isArray arr
            throw new Meteor.Error "Expected an array"

        J.Dict.fromDeepObjOrArr arr