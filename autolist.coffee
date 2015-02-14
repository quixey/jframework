class J.AutoList extends J.List
    constructor: (tag, sizeFunc, valueFunc, onChange) ->
        unless @ instanceof J.AutoList
            return new J.AutoList tag, sizeFunc, valueFunc, onChange

        if _.isFunction tag
            # Alternate signature: J.AutoList(sizeFunc, valueFunc, onChange)
            onChange = valueFunc
            valueFunc = sizeFunc
            sizeFunc = tag
            tag = undefined

        unless _.isFunction(sizeFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoList must be constructed with sizeFunc and valueFunc"

        super [],
            creator: Tracker.currentComputation
            onChange: null # doesn't support onChange=true
            tag: tag

        @sizeFunc = sizeFunc
        @valueFunc = valueFunc
        @onChange = onChange

        @_dict = J.AutoDict(
            (
                autoList: @
                tag: "#{@toString()}._dict"
            )

            =>
                size = @sizeFunc()
                unless _.isNumber(size) and parseInt(size) is size and size >= 0
                    throw new Meteor.Error "Invalid AutoList sizeFunc output: #{size}"
                "#{i}" for i in [0...size]

            (key, _dict) => @valueFunc parseInt(key), @

            (
                if _.isFunction @onChange then (key, oldValue, newValue) =>
                    @onChange?.call @, parseInt(key), oldValue, newValue
                else
                    @onChange
            )
        )


    clone: ->
        throw new Meteor.Error "There is no AutoList.clone.
            You should be able to either use the same AutoList
            or else call snapshot()."


    clear: ->
        throw new Meteor.Error "There is no AutoList.clear"


    get: ->
        getter = Tracker.currentComputation
        canGet = @isActive() or (getter? and getter is @creator)
        if not canGet
            throw new Meteor.Error "Can't get field of inactive #{@constructor.name}: #{@}"

        super


    push: ->
        throw new Meteor.Error "There is no AutoList.push"


    resize: ->
        throw new Meteor.Error "There is no AutoList.resize"


    reverse: ->
        throw new Meteor.Error "There is no AutoList.reverse"


    set: ->
        throw new Meteor.Error "There is no AutoList.set"


    snapshot: ->
        keys = Tracker.nonreactive => @_dict.getKeys()
        if keys is undefined
            undefined
        else
            J.List Tracker.nonreactive => @getValues()


    size: ->
        getter = Tracker.currentComputation
        canGet = @isActive() or (getter? and getter is @creator)
        if not canGet
            throw new Meteor.Error "Can't get size of inactive #{@constructor.name}: #{@}"

        super


    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"


    stop: ->
        @_dict.stop()


    toString: ->
        s = "AutoList[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if @_dict? and not @isActive() then s += " (inactive)"
        s