class J.AutoDict extends J.Dict
    constructor: (keysFunc, valueFunc, onChange = null, equalsFunc = J.util.equals) ->
        unless @ instanceof J.AutoDict
            return new J.AutoDict keysFunc, valueFunc, onChange, equalsFunc

        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        super {}, equalsFunc

        @valueFunc = valueFunc

        ###
            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoDict becomes non-lazy.
        ###
        @onChange = onChange

        @_keysComp = null
        @keysFunc = null

        @active = true

        @replaceKeysFunc keysFunc

    _delete: (key) ->
        @_fields[key].stop()
        super

    _initField: (key) ->
        @_fields[key] = Tracker.nonreactive => J.AutoVar(
            => @valueFunc.call null, key
            (
                if _.isFunction @onChange then (oldValue, newValue) =>
                    @onChange?.call @, key, oldValue, newValue
                else
                    @onChange
            )
            @equalsFunc
        )
        super

    _setupKeysFunc: ->
        @_keysComp?.stop()
        @_keysComp = Tracker.nonreactive => Tracker.autorun (c) =>
            newKeys = @keysFunc.apply null
            if newKeys instanceof J.List then newKeys = newKeys.toArr()

            if newKeys is null
                @_clear()
            else if _.isArray newKeys
                unless _.all (_.isString(key) for key in newKeys)
                    throw new Meteor.Error "AutoDict keys must all be type string."
                if _.size(J.util.makeDictSet newKeys) < newKeys.length
                    throw new Meteor.Error "AutoDict keys must be unique."
                @_replaceKeys newKeys
            else
                throw new Meteor.Error "AutoDict.keysFunc must return an array or null. Got #{newKeys}"

    clear: ->
        throw new Meteor.Error "There is no AutoDict.clear"

    delete: ->
        throw new Meteor.Error "There is no AutoDict.delete"

    forceGet: ->
        unless @active
            throw new Meteor.Error "AutoDict is stopped"
        super

    get: ->
        unless @active
            throw new Meteor.Error "AutoDict is stopped"
        super

    getKeys: ->
        if @_keysComp.invalidated
            @_setupKeysFunc()
        super

    hasKey: ->
        if @_keysComp.invalidated
            @_setupKeysFunc()
        super

    replaceKeys: ->
        throw new Meteor.Error "There is no AutoDict.replaceKeys; use AutoDict.replaceKeysFunc"

    replaceKeysFunc: (keysFunc) ->
        @keysFunc = keysFunc
        @_setupKeysFunc()

    replaceValueFunc: (@valueFunc) ->
        # autoVar.replaceValueFunc would be overkill because the individual
        # AutoVars' valueFuncs are closures that will automatically
        # reference this updated @valueFunc.
        autoVar._valueComp.invalidate() for key, autoVar of @_fields

    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"

    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keysFunc and AutoDict.valueFunc"

    stop: ->
        if @active
            @_keysComp.stop()
            @_fields[key].stop() for key in @_fields
            @active = false

    toString: ->
        # Reactive
        "AutoDict#{J.util.stringify @toObj()}"