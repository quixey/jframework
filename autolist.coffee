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
            onChange: null # doesn't support onChange=true
            tag: tag

        @onChange = onChange

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

        @_valuesVar = J.AutoVar(
            (
                autoList: @
                tag: "#{@toString()} valuesVar"
            )

            =>
                size = @size()
                ready = true

                values = for i in [0...size]
                    try
                        @valueFunc.call null, i, @
                    catch e
                        if e instanceof J.VALUE_NOT_READY
                            # This is how AutoLists are parallelized. We keep
                            # looping because we want to synchronously register
                            # all the not-ready computations with the data
                            # fetcher that runs during afterFlush.
                            ready = false
                            undefined
                        else
                            throw e

                throw J.makeValueNotReadyObject() if not ready

                # Side effects during AutoVar recompute functions are usually not okay.
                # We just need the framework to do it in this one place.
                for i in [0...Math.min size, @_arr.length]
                    @_set i, values[i]

                if size < @_arr.length
                    for i in [size...@_arr.length]
                        @_pop()
                else if size > @_arr.length
                    for i in [@_arr.length...size]
                        @_push values[i]

                null

            if @onChange? then true else null

            creator: @creator
        )


    _get: (index) ->
        if @_valuesVar.get() is undefined
            undefined
        else
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


    snapshot: ->
        values = Tracker.nonreactive => @getValues()
        if values is undefined
            undefined
        else
            J.List values


    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"


    stop: ->
        @_valuesVar.stop()
        @_sizeVar.stop()


    toString: ->
        s = "AutoList[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s