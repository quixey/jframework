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

                # Side effects during AutoVar recompute functions are usually not okay.
                # We just need the framework to do it in this one place.
                if size < @_arr.length
                    for i in [size...@_arr.length]
                        @_pop()
                else if size > @_arr.length
                    for i in [@_arr.length...size]
                        @_push()

                size

            if @onChange? then true else null

            creator: @creator
        )


    _get: (index) ->
        if @size() is undefined
            undefined
        else
            if @_arr[index] is null then @_initFieldAutoVar index
            @_arr[index].get()


    _initFieldAutoVar: (index) ->
        @_arr[index] = J.AutoVar(
            (
                autoList: @
                fieldIndex: index
                tag: "#{@toString()}._fields[#{index}]"
            )

            =>
                # If @_sizeVar needs recomputing, this .get() call
                # will throw a COMPUTING. Then this field-autovar
                # may or may not be left standing to recompute
                # and continue past the assert.
                J.assert index < @size(), "SIZE"

                @valueFunc.call null, index, @

            if _.isFunction @onChange
                @onChange.bind @, index
            else
                @onChange

            creator: @creator
        )


    _pop: ->
        fieldAutoVar = @_arr[@_arr.length - 1]
        super
        fieldAutoVar?.stop()


    _push: ->
        index = @_arr.length

        @_arr.push null

        if @onChange
            @_initFieldAutoVar index
        else
            # Save ~1kb of memory until the field is
            # actually needed.


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
        fieldVar?.stop() for fieldVar in @_arr
        @_sizeVar.stop()


    toString: ->
        s = "AutoList[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s