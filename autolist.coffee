class J.AutoList extends J.List
    constructor: (tag, sizeFunc, valueFunc, onChange) ->
        unless @ instanceof J.AutoList
            return new J.AutoList tag, sizeFunc, valueFunc, onChange

        if _.isFunction(tag) or _.isNumber(tag)
            # Alternate signature: J.AutoList(sizeFunc, valueFunc, onChange)
            onChange = valueFunc
            valueFunc = sizeFunc
            sizeFunc = tag
            tag = undefined

        if _.isNumber(sizeFunc)
            @sizeFunc = -> sizeFunc
        else
            @sizeFunc = sizeFunc

        @valueFunc = valueFunc

        unless _.isFunction(@sizeFunc) and _.isFunction(@valueFunc)
            throw new Meteor.Error "AutoList must be constructed with sizeFunc and valueFunc"

        super [],
            creator: Tracker.currentComputation
            onChange: onChange
            tag: tag

        @_sizeDep = null

        @_sizeVar = J.AutoVar(
            (
                autoList: @
                tag: "#{@toString()} sizeVar"
            )

            =>
                size = @sizeFunc.apply null

                unless _.isNumber(size) and size is parseInt(size) and size >= 0
                    throw new Meteor.Error "AutoList.sizeFunc must return an int.
                        Got #{size}"

                size

            if @onChange? then true else null

            creator: @creator
        )

        @_valuesAutoVar = J.AutoVar(
            (
                autoList: @
                tag: "#{@toString()} valuesAutoVar"
            )

            =>
                oldSize = Tracker.nonreactive => J.List::size.call @
                size = @size()

                values = for i in [0...size]
                    try
                        @valueFunc.call null, i, @
                    catch e
                        if e instanceof J.VALUE_NOT_READY
                            # This is how AutoLists are parallelized. We keep
                            # looping because we want to synchronously register
                            # all the not-ready computations with the data
                            # fetcher that runs during afterFlush.
                            e
                        else
                            throw e

                # Side effects during AutoVar recompute functions are usually not okay.
                # We just need the framework to do it in this one place.
                for i in [0...Math.min oldSize, size]
                    Tracker.nonreactive => @_set i, values[i]

                    # Setting may have caused @creator to invalidate which
                    # in turn killed @. Normally we never need this kind of
                    # hacky bailout; it's just because we're doing mutation
                    # in a valueComp.
                    if not @isActive()
                        return J.makeValueNotReadyObject()

                if size < oldSize
                    for i in [size...oldSize]
                        Tracker.nonreactive => @_pop()
                else if oldSize < size
                    for i in [oldSize...size]
                        Tracker.nonreactive => @_push values[i]

                null

            if @onChange? then true else null

            creator: @creator
        )


    _get: (index) ->
        # Call @_valuesAutoVar.get() for its side effect if
        # @_valuesAutoVar is newly created or invalidated.
        @_valuesAutoVar.get()
        super


    clone: ->
        throw new Meteor.Error "There is no AutoList.clone.
            You should be able to either use the same AutoList
            or else call snapshot()."


    clear: ->
        throw new Meteor.Error "There is no AutoList.clear"


    isActive: ->
        not @_sizeVar?.stopped


    push: ->
        throw new Meteor.Error "There is no AutoList.push"


    reverse: ->
        throw new Meteor.Error "There is no AutoList.reverse"


    set: ->
        throw new Meteor.Error "There is no AutoList.set"


    size: ->
        @_sizeVar.get()


    splice: ->
        throw new Meteor.Error "There is no AutoList.splice"


    snapshot: ->
        values = Tracker.nonreactive => @getValues()
        if values is undefined
            undefined
        else
            J.List values


    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"


    stop: ->
        @_valuesAutoVar.stop()
        @_sizeVar.stop()


    toString: ->
        s = "AutoList[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s