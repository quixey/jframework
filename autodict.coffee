class J.AutoDict extends J.Dict
    constructor: (keysFunc, valueFunc, onChange = null, equalsFunc = J.util.equals) ->
        unless @ instanceof J.AutoDict
            return new J.AutoDict keysFunc, valueFunc, onChange, equalsFunc

        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        super {}, equalsFunc

        @keysFunc = keysFunc
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

        @_keysVar = J.AutoVar(
            =>
                newKeys = @keysFunc.apply null

                if newKeys instanceof J.List
                    newKeys = newKeys.toArr()
                else if newKeys is null
                    newKeys = []

                if _.isArray newKeys
                    unless _.all (_.isString(key) for key in newKeys)
                        throw new Meteor.Error "AutoDict keys must all be type string.
                            Got #{J.util.stringify newKeys}"
                    if _.size(J.util.makeDictSet newKeys) < newKeys.length
                        throw new Meteor.Error "AutoDict keys must be unique."
                    newKeys
                else
                    throw new Meteor.Error "AutoDict.keysFunc must return an array
                        or null. Got #{newKeys}"
                newKeys
            (oldKeys, newKeys) =>
                @_replaceKeys newKeys
            J.util.equals
            false
        )
        @_keysVar.tag = "AutoDict._keysVar"

        @active = true
        if Tracker.active then Tracker.onInvalidate => @stop()

    _delete: (key) ->
        @_fields[key].stop()
        super

    _get: (key, force) ->
        if @hasKey key
            if key not of @_fields
                # Key would have been initialized at Tracker.flush time
                @_initField key
            @_fields[key].get()
        else if force
            throw new Meteor.Error "#{@constructor.name} missing key #{J.util.stringify key}"
        else
            undefined

    _initField: (key) ->
        @_fields[key] = Tracker.nonreactive => J.AutoVar(
            =>
                # In the AutoVar graph, set up the dependency
                # @_keysVar -> @_fields[key]
                if @hasKey key
                    @valueFunc.call null, key
                else
                    # @_delete(key) should be called during
                    # @_keysVar.onChange after flush
                    J.AutoVar._UNDEFINED
            (
                if _.isFunction @onChange then (oldValue, newValue) =>
                    @onChange?.call @, key, oldValue, newValue
                else
                    @onChange
            )
            @equalsFunc
        )
        @_fields[key].tag = "AutoDict._fields[#{J.util.stringify key}]"
        super

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
        @_keysVar.get()

    hasKey: (key) ->
        @_keysVar.contains key

    replaceKeys: ->
        throw new Meteor.Error "There is no AutoDict.replaceKeys; use AutoDict.replaceKeysFunc"

    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"

    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keysFunc and AutoDict.valueFunc"

    stop: ->
        if @active
            @_keysVar.stop()
            @_fields[key].stop() for key of @_fields
            @active = false

    toString: ->
        # Reactive
        "AutoDict#{J.util.stringify @toObj()}"