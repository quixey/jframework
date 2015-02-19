###
    TODO: Add a @observe() and @observeChanges() just like
    Meteor's collection API. Good for List and AutoList.
###


class J.List
    constructor: (values, options) ->
        ###
            Options:
                creator: The computation which "created"
                    this Dict, which makes it inactive
                    when it invalidates.
                tag: A toString-able object for debugging
                onChange: function(key, oldValue, newValue) or null
        ###

        unless @ instanceof J.List
            return new J.List values, options

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        @tag = options?.tag

        if values instanceof J.List
            @tag ?=
                constructorCloneOf: values
                tag: "#{@constructor.name} clone of (#{values.toString()})"
            arr = values.getValues()
        else if _.isArray values
            arr = values
        else if not values?
            arr = []
        else
            throw new Meteor.Error "#{@constructor} values argument must be a List or
                array. Got: #{values}"

        if options?.creator is undefined
            @creator = Tracker.currentComputation
        else
            @creator = options.creator
        @onChange = options?.onChange ? null

        @readOnly = false

        fields = {}
        for x, i in arr
            fields[i] = x

        @_dict = J.Dict fields,
            creator: @creator
            tag:
                list: @
                tag: "#{@toString()}._dict"
            onChange: if @onChange?
                (key, oldValue, newValue) =>
                    @onChange.call @, parseInt(key), oldValue, newValue


    _resize: (size) ->
        @_dict.replaceKeys ("#{i}" for i in [0...size])


    clear: ->
        @resize 0


    clone: ->
        # Nonreactive because a clone's fields are their
        # own new piece of application state
        valuesSnapshot = Tracker.nonreactive => @getValues()
        @constructor valuesSnapshot, _.extend(
            {
                creator: Tracker.currentComputation
                tag:
                    clonedFrom: @
                    tag: "clone of #{@toString}"
                onChange: null
            }
        )


    contains: (value) ->
        # The current implementation invalidates somewhat
        # too much.
        # We could make the reactivity more efficient by
        # using a special hashSet of @_containsDeps
        # (one per value argument), but it would be
        # tricky to handle calls to @contains(v)
        # when v isn't J.Dict.encodeKey-able.
        @indexOf(value) >= 0


    debug: ->
        console.log @toString()
        for key, v of @_dict._fields
            console.group key
            v.debug()
            console.groupEnd()


    extend: (values) ->
        size = Tracker.nonreactive => @size()
        adder = {}
        for value, i in @constructor.unwrap values
            adder["#{size + i}"] = value
        @_dict.setOrAdd adder


    find: (f = _.identity) ->
        for i in [0...@size()]
            x = @get i
            return x if f x


    filter: (f = _.identity) ->
        # Parallelize running the filter function
        filterOutputs = @map(f).getValues()
        filtered = J.List [],
            tag:
                filteredFrom: @
                filterFunc: f
                tag: "filtered #{@toString()}"
        @forEach (v, i) ->
            if filterOutputs[i] then filtered.push v
        filtered


    forEach: (f) ->
        ###
            Use when f has side effects.
            Like @map except:
            - Lets f return undefined
            - Returns an array, not an AutoList
            - Invalidates when @getValues() changes,
              not when the returned array changes.
        ###
        callerComp = Tracker.currentComputation
        UNDEFINED = new J.Dict()
        mappedList = @map (v, i) ->
            if callerComp
                # There's no such thing as partially invalidating
                # the output of a forEach, since the whole thing
                # is supposed to cause one big side effect.
                # If a value of this list changes, or another
                # reactive input to f changes, then the caller
                # of the forEach should get invalidated.
                Tracker.onInvalidate -> callerComp.invalidate()
            ret = f v, i
            if ret is undefined then UNDEFINED else ret
        for value in mappedList.getValues()
            if value is UNDEFINED then undefined else value


    get: (index) ->
        unless _.isNumber(index)
            throw new Meteor.Error "Index must be a number"

        @_dict.forceGet "#{index}"


    getConcat: (lst) ->
        if Tracker.active
            lst = @constructor.wrap lst
            J.AutoList(
                =>
                    @size() + lst.size()
                (i) =>
                    if i < @size()
                        @get i
                    else
                        lst.get i - @size()
            )
        else
            J.List @getValues().concat @constructor.unwrap lst


    getReversed: ->
        @map (value, i) => @get @size() - 1 - i


    getSorted: (keySpec = J.util.sortKeyFunc) ->
        sortKeys = @map(J.util._makeSortKeyFunc keySpec).getValues()
        items = _.map @getValues(), (v, i) => index: i, value: v
        J.List(
            _.map(
                J.util.sortByKey items, (item) => sortKeys[item.index]
                (item) => item.value
            )
            tag:
                sortedFrom: @
                sortKeySpec: keySpec
                tag: "sorted #{@toString()}"
        )


    getValues: ->
        @_dict.get "#{i}" for i in [0...@size()]


    join: (separator) ->
        @map().getValues().join separator


    indexOf: (x, equalsFunc = J.util.equals) ->
        for i in [0...@size()]
            y = @get i
            return i if equalsFunc y, x
        -1


    isActive: ->
        @_dict.isActive()


    lazyMap: (f = _.identity) ->
        if Tracker.active
            J.AutoList(
                => @size()
                (i) => f @get(i), i
                null # This makes it lazy
            )
        else
            J.List @getValues().map f


    map: (f = _.identity) ->
        # Enables parallel fetching
        if Tracker.active
            if f is _.identity and @ instanceof J.AutoList and @onChange
                @
            else
                mappedAl = J.AutoList(
                    "mapped #{@toString()}"
                    => @size()
                    (i) => f @get(i), i
                    true # This makes it not lazy
                )
        else
            J.List @getValues().map(f), "mapped #{@toString()}"


    push: (value) ->
        @extend [value]


    pop: ->
        size = Tracker.nonreactive => @size()
        if size is 0
            undefined
        else
            lastValue = @get size - 1
            @_dict.delete "#{size - 1}"
            lastValue


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
        setter["#{index}"] = value
        @_dict.set setter


    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @_dict.setReadOnly @readOnly, deep


    sort: (keySpec = J.util.sortKeyFunc) ->
        sortedArr = Tracker.nonreactive => @getSorted(keySpec).toArr()
        @set i, sortedArr[i] for i in [0...sortedArr.length]
        null


    size: ->
        @_dict.size()


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
        s = "List[#{@_id}]"
        if @tag then s += "(#{J.util.stringifyTag @tag})"
        if @_dict? and not @isActive() then s += " (inactive)"
        s


    tryGet: (index) ->
        if @_dict.hasKey "#{index}"
            J.tryGet => @get index
        else
            undefined


    @unwrap: (listOrArr) ->
        if listOrArr instanceof J.List
            listOrArr.getValues()
        else if _.isArray listOrArr
            listOrArr
        else
            throw new Meteor.Error "#{@constructor.name} can't unwrap #{listOrArr}"


    @wrap: (listOrArr) ->
        if listOrArr instanceof @
            listOrArr
        else if _.isArray listOrArr
            @ listOrArr
        else
            throw new Meteor.Error "#{@constructor.name} can't wrap #{listOrArr}"