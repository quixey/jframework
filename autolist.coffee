class J.AutoList extends J.List
    constructor: (sizeFunc, valueFunc, onChange = null, equalsFunc = J.util.equals) ->
        unless @ instanceof J.AutoList
            return new J.AutoList sizeFunc, valueFunc, onChange, equalsFunc

        unless _.isFunction(sizeFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoList must be constructed with sizeFunc and valueFunc"

        @_id = J.AutoVar._nextId
        J.AutoVar._nextId += 1
        J.AutoVar._byId[@_id] = @

        super [], equalsFunc

        @sizeFunc = sizeFunc
        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc

        @_creatorComp = Tracker.currentComputation
        @active = true

        init = true
        if Tracker.active then Tracker.onInvalidate (c) =>
            if init
                console.log "Invalidated computation is creating an AutoList", c.tag
                console.trace()
                # We have a J.Dict from calling super
                @_dict = null
            @stop()
        init = false
        return unless @active

        @_dict = Tracker.nonreactive => J.AutoDict(
            =>
                @_dict.tag = @tag #FIXME: awkward place for this
                size = @sizeFunc()
                unless _.isNumber(size) and parseInt(size) is size and size >= 0
                    throw "Invalid AutoList sizeFunc output: #{size}"
                "#{i}" for i in [0...size]
            (key) => @valueFunc parseInt(key)
            (
                if _.isFunction @onChange then (key, oldValue, newValue) =>
                    @onChange?.call @, parseInt(key), oldValue, newValue
                else
                    @onChange
            )
            @equalsFunc
        )

    clone: ->
        throw new Meteor.Error "There is no AutoList.clone.
            You should be able to either use the same AutoList
            or else call snapshot()."

    clear: ->
        throw new Meteor.Error "There is no AutoList.clear"

    get: ->
        unless @active
            console.log "AutoList", @tag
            if @_dict?
                @_dict.logDebugInfo()
            else
                console.log "@_dict is null"
            throw new Meteor.Error "AutoList is stopped"
        super

    push: ->
        throw new Meteor.Error "There is no AutoList.push"

    resize: ->
        throw new Meteor.Error "There is no AutoList.resize"

    reverse: ->
        throw new Meteor.Error "There is no AutoList.reverse"

    set: ->
        throw new Meteor.Error "There is no AutoList.set"

    setDebug: (@debug) ->
        @_dict.setDebug debug

    snapshot: ->
        keys = Tracker.nonreactive => @_dict.getKeys()
        if keys is undefined
            undefined
        else
            J.List Tracker.nonreactive => @getValues()

    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"

    stop: ->
        # console.log "STOPPING (#{@tag}) created by (#{@_creatorComp?.tag})"
        @_dict?.stop() # Could be stopped at construct time
        @active = false

    toString: ->
        # Reactive
        objString =
            if @active
                J.util.stringify @toArr()
            else
                "STOPPED"
        "AutoList(#{@tag ? ''},#{@_id}=#{objString})"