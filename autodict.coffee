class J.AutoDict extends J.Dict
    constructor: (keysFunc, @valueFunc, @onChange = null, @equalsFunc = J.util.equals) ->
        unless _.isFunction(keysFunc) and _.isFunction(@valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        @_fields = {} # key: AutoVar
        @_hasKeyDeps = {} # realOrImaginedKey: Dependency
        @_keysDep = new Deps.Dependency()

        @active = true

        @_keysComp = null

        @keysFunc = null
        @replaceKeysFunc keysFunc

    _initField: (key) ->
        @_fields[key] = new J.AutoVar(
            => @valueFunc.call key
            (oldValue, newValue) => @onChange?.call null, key, oldValue, newValue
            @equalsFunc
        )

    clear: ->
        throw new Meteor.Error "There is no AutoDict.clear"

    delete: ->
        throw new Meteor.Error "There is no AutoDict.delete"

    replaceKeys: ->
        throw new Meteor.Error "There is no AutoDict.replaceKeys; use AutoDict.replaceKeysFunc"

    replaceKeysFunc: (keysFunc) ->
        @_keysComp?.stop()
        @keysFunc = keysFunc
        @_keysComp = Tracker.nonreactive => Tracker.autorun (c) =>
            newKeys = @keysFunc.apply null
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

    replaceValueFunc: (@valueFunc) ->
        # autoVar.replaceValueFunc would be overkill because the individual
        # AutoVars' valueFuncs are closures that will automatically
        # reference this updated @valueFunc.
        autoVar._valueComp.invalidate() for key, autoVar of @_fields

    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"

    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keyFunc and AutoDict.valueFunc"

    stop: ->
        if @active
            @_keysComp.stop()
            autoVar.stop() for key, autoVar in @_fields
            @active = false
        null