class J.FineGrainedAutoList extends J.List
    constructor: (tag, sizeFunc, valueFunc, onChange) ->
        unless @ instanceof J.FineGrainedAutoList
            return new J.FineGrainedAutoList tag, sizeFunc, valueFunc, onChange

        if _.isFunction(tag) or _.isNumber(tag)
            # Alternate signature: J.FineGrainedAutoList(sizeFunc, valueFunc, onChange)
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
            throw new Meteor.Error "FineGrainedAutoList must be constructed with sizeFunc and valueFunc"

        super [],
            creator: Tracker.currentComputation
            onChange: null # doesn't support onChange=true
            tag: tag

        @onChange = onChange

        @_sizeDep = null

        @_sizeVar = J.AutoVar(
            (
                fineGrainedAutoList: @
                tag: "#{@toString()} sizeVar"
            )

            =>
                size = @sizeFunc.apply null

                unless _.isNumber(size) and size is parseInt(size) and size >= 0
                    throw new Meteor.Error "FineGrainedAutoList.sizeFunc must return an int.
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
                fineGrainedAutoList: @
                fieldIndex: index
                tag: "#{@toString()}._fields[#{index}]"
            )

            =>
                if index >= @size()
                    # This field has just been popped
                    return J.makeValueNotReadyObject()

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
        throw new Meteor.Error "There is no FineGrainedAutoList.clone.
            You should be able to either use the same FineGrainedAutoList
            or else call snapshot()."


    clear: ->
        throw new Meteor.Error "There is no FineGrainedAutoList.clear"


    isActive: ->
        not @_sizeVar?.stopped


    push: ->
        throw new Meteor.Error "There is no FineGrainedAutoList.push"


    reverse: ->
        throw new Meteor.Error "There is no FineGrainedAutoList.reverse"


    set: ->
        throw new Meteor.Error "There is no FineGrainedAutoList.set"


    size: ->
        @_sizeVar.get()


    snapshot: ->
        values = Tracker.nonreactive => @getValues()
        if values is undefined
            undefined
        else
            J.List values


    sort: ->
        throw new Meteor.Error "There is no FineGrainedAutoList.sort"


    stop: ->
        fieldVar?.stop() for fieldVar in @_arr
        @_sizeVar.stop()


    toString: ->
        s = "FineGrainedAutoList[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s