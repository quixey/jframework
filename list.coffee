###
    TODO: Add a @observe() and @observeChanges() just like
    Meteor's collection API. Good for List and AutoList.
###


class J.List
    @_UNDEFINED = new (->)

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

        @tag = if J.debugTags then options?.tag else null

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

        # compact mode
        @_valuesVar = J.Var(
            J.Var.wrap v for v in arr

            tag:
                list: @
                tag: "#{@toString()} valuesVar"
            creator: @creator
            wrap: false
            onChange:
                if _.isFunction @onChange
                    (oldValues, newValues) =>
                        for i in [0...Math.max oldValues.length, newValues.length]
                            if oldValues[i] isnt newValues[i]
                                @onChange i, oldValues[i], newValues[i]
        )

        # expanded mode
        @_arr = null
        @_sizeDep = null



    _get: (index) ->
        if @_valuesVar?
            # We're using a J.Var to:
            # - throw VALUE_NOT_READY
            # - set an extra dependency for List/Dict creator invalidations
            J.Var(@_valuesVar.get()[index]).get()

        else
            unless @_arr[index] instanceof J.Var
                @_initIndexVar index
            @_arr[index].get()


    _initIndexVar: (index) ->
        # Initialize it as not-ready so when we set it
        # on the next line, it might trigger @onChange.
        @_arr[index] = J.Var @_arr[index],
            creator: @creator
            tag:
                list: @
                index: index
                tag: "#{@toString()}._arr[#{index}]"
            onChange:
                if _.isFunction @onChange
                    @onChange.bind @, index
                else null


    _pop: ->
        if Tracker.active then @_setCompact false

        if @_valuesVar?
            values = _.clone Tracker.nonreactive => @_valuesVar.get()
            lastValue = values.pop()
            @_valuesVar.set values
            return J.Var(lastValue).get()

        size = @_arr.length
        if size is 0
            undefined
        else
            lastValue = undefined
            Tracker.nonreactive =>
                if @_arr[size - 1] instanceof J.Var
                    lastValue = @_arr[size - 1]._value
                    if lastValue is undefined or lastValue instanceof J.VALUE_NOT_READY
                        lastValue = @_arr[size - 1]._previousReadyValue
                else
                    lastValue = @_arr[size - 1]
            if lastValue isnt undefined and _.isFunction @onChange
                Tracker.afterFlush =>
                    if @isActive()
                        @onChange.call @, size - 1, lastValue, undefined
            @_arr.pop()
            @_sizeDep?.changed()
            lastValue


    _push: (value) ->
        if Tracker.active then @_setCompact false

        if @_valuesVar?
            values = _.clone Tracker.nonreactive => @_valuesVar.get()
            values.push J.Var.wrap value
            @_valuesVar.set values
            return

        index = @_arr.length

        if (
            _.isFunction(@onChange) or
            value instanceof J.List or value instanceof J.Dict or
            _.isArray(value) or J.util.isPlainObject(value) or
            value instanceof J.VALUE_NOT_READY
        )
            @_arr.push J.makeValueNotReadyObject()
            @_initIndexVar index
            @_arr[index].set value
        else
            @_arr.push value

        @_sizeDep?.changed()


    _set: (index, value) ->
        if Tracker.active then @_setCompact false

        if @_valuesVar?
            values = _.clone Tracker.nonreactive => @_valuesVar.get()
            values[index] = J.Var.wrap value
            @_valuesVar.set values
            return value

        if not @isActive()
            throw new Meteor.Error "Can't set value of inactive #{@constructor.name}: #{@}"

        unless index of @_arr
            throw new Meteor.Error "List index out of range"

        if @_arr[index] not instanceof J.Var
            # We need a Var to set this object up to invalidate getters
            # when its creator invalidates.
            if (
                value instanceof J.List or value instanceof J.Dict or
                _.isArray(value) or J.util.isPlainObject(value) or
                value instanceof J.VALUE_NOT_READY
            )
                @_initIndexVar index

        if @_arr[index] instanceof J.Var
            @_arr[index].set value
        else
            @_arr[index] = value


    _setCompact: (compact) ->
        ###
            Compact mode:
                @_valuesVar is just one array of values; it doesn't
                try to wrap them in individual Vars or monitor
                individual gets at index-granularity.
            Expanded mode:
                @_arr is an array of naked values that get
                promoted to Vars as needed.
        ###

        if compact
            throw "not implemented yet"
        else
            return if @_arr?

            J.inc 'setCompact'

            values = Tracker.nonreactive => @getValues()

            # Invalidate its dependents so they recompute and
            # get a more granular dependency.
            @_valuesVar.set null
            @_valuesVar = null

            @_arr = []
            @_push value for value in values
            @_sizeDep = new Tracker.Dependency @creator


    clear: ->
        @pop() for i in [0...Tracker.nonreactive -> @size()]


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
        for v, i in arr
            console.group i
            v.debug()
            console.groupEnd()


    extend: (values) ->
        size = Tracker.nonreactive => @size()
        for value in (Tracker.nonreactive => @constructor.unwrap values)
            @push value


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
        J.forEachIds[@_id] = true
        ###
            Use when f has side effects.
            Like @map except:
            - Lets f return undefined
            - Returns an array, not an AutoList
            - Invalidates when @getValues() changes,
              not when the returned array changes.
        ###
        callerComp = Tracker.currentComputation
        mappedList = @map(
            (v, i) =>
                if callerComp
                    # There's no such thing as partially invalidating
                    # the output of a forEach, since the whole thing
                    # is supposed to cause one big side effect.
                    # If a value of this list changes, or another
                    # reactive input to f changes, then the caller
                    # of the forEach should get invalidated.
                    Tracker.onInvalidate -> callerComp.invalidate()
                ret = f v, i
                if ret is undefined then J.List._UNDEFINED else ret
            tag:
                tag: "forEach(#{@toString()})"
                sourceList: @
                mapFunc: f
        )
        for value in mappedList.getValues()
            if value is J.List._UNDEFINED then undefined else value


    get: (index) ->
        J.getIds[@_id] = true

        if not @isActive()
            throw new Meteor.Error "Computation #{Tracker.currentComputation?._id}
                can't get index #{index} of inactive #{@constructor.name}: #{@}"

        unless _.isNumber(index) and parseInt(index) is index
            throw new Meteor.Error "Index must be an int"

        size = Tracker.nonreactive => @size()

        if index < 0
            index = size + index

        unless 0 <= index < size
            throw new Meteor.Error "List index out of range"

        @_get index


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
        J.getValueIds[@_id] = true

        @get(i) for i in [0...@size()]


    join: (separator) ->
        @map().getValues().join separator


    indexOf: (x, equalsFunc = J.util.equals) ->
        for i in [0...@size()]
            y = @get i
            return i if equalsFunc y, x
        -1


    isActive: ->
        not @creator?.invalidated


    map: (f = _.identity, tag) ->
        J.mapIds[@_id] = true

        # Enables parallel fetching
        tag ?= (
            tag: "mapped(#{@toString()})"
            sourceList: @
            mapFunc: f
        )
        if @size() is undefined then return undefined
        J.List(
            for i in [0...@size()]
                try
                    v = @get i
                    if v is undefined then undefined else f v, i
                catch e
                    if e instanceof J.VALUE_NOT_READY
                        # This is how AutoLists are parallelized. We keep
                        # looping because we want to synchronously register
                        # all the not-ready computations with the data
                        # fetcher that runs during afterFlush.
                        e
                    else
                        throw e
            tag: tag
        )


    push: (value) ->
        @_push value
        undefined


    pop: ->
        @_pop()


    reverse: ->
        reversedArr = Tracker.nonreactive => @getReversed().toArr()
        @set i, reversedArr[i] for i in [0...reversedArr.length]
        null


    rFind: (f = _.identity) ->
        for i in [@size() - 1..0]
            x = @get i
            return x if f x


    set: (index, value) ->
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"

        @_set index, value


    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            J.Dict._deepSetReadOnly Tracker.nonreactive => @getValues()


    slice: (startIndex, endIndex = @size()) ->
        if Tracker.active
            J.AutoList(
                =>
                    Math.max 0,
                        Math.min(@size(), endIndex) - startIndex
                (i) => @get startIndex + i
            )
        else
            J.List @getValues().slice startIndex, endIndex


    sort: (keySpec = J.util.sortKeyFunc) ->
        sortedArr = Tracker.nonreactive => @getSorted(keySpec).toArr()
        @set i, sortedArr[i] for i in [0...sortedArr.length]
        null


    size: ->
        if not @isActive()
            throw new Meteor.Error "Can't get size of inactive #{@constructor.name}: #{@}"

        if @_valuesVar?
            @_valuesVar.get().length
        else
            @_sizeDep.depend()
            @_arr.length


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
        if not @isActive() then s += " (inactive)"
        s


    tryGet: (index) ->
        if index < @size()
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