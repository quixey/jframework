class J.AutoDict extends J.Dict
    constructor: (keysFunc, valueFunc, @onChange = null, @equalsFunc = J.util.equals) ->
        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        @_fields = {} # key: ReactiveVar
        @_hasKeyDeps = {} # realOrImaginedKey: Dependency

        @keysFunc = null
        @valueFunc = valueFunc

        @active = true
        @_keysComp = null
        @_valueComps = {} # key: valueComp

        @replaceKeysFunc keysFunc

    _initField: (key) ->
        @_fields[key] = new ReactiveVar undefined, @equalsFunc
        @_setupValueComp key

        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _recompute: (key) ->
        oldValue = Tracker.nonreactive => @_fields[key].get()
        newValue = @valueFunc.call null, key
        if newValue is undefined
            throw new Meteor.Error "AutoDict.valueFunc must not return undefined"

        @_fields[key].set newValue

        unless @equalsFunc oldValue, newValue
            @onChange?.call null, key, oldValue, newValue

    _clear: ->
        for key of @_fields
            @_delete key

    _delete: (key) ->
        if key of @_fields
            @_valueComps[key].stop()
            delete @_valueComps[key]
        @constructor._deepStop @_fields[key]
        delete @_fields[key]

        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _replaceKeys: (newKeys) ->
        keysDiff = J.Dict.diff @keys(), newKeys
        @_delete key for key in keysDiff.deleted
        @_initField key for key in keysDiff.added
        keysDiff

    _setupValueComp: (key) ->
        if @_valueComps[key]?
            @_valueComps[key].stop()

        @_valueComps[key] = Tracker.nonreactive => Tracker.autorun (c) =>
            @_recompute key

    clear: ->
        throw new Meteor.Error "There is no AutoDict.clear"

    delete: ->
        throw new Meteor.Error "There is no AutoDict.delete"

    get: (key, defaultValue) ->
        unless @active
            throw new Meteor.Error "AutoDict is stopped"

        unless @hasKey(key)
            if arguments.length >= 2
                return defaultValue
            else
                throw new Meteor.Error "AutoDict missing key #{JSON.stringify key}"

        if @_valueComps[key].invalidated
            # Accessing an invalidated key before Meteor's flush has had a
            # chance to recompute it. We'll effectively move it to the front
            # of the flush queue so it never returns an invalidated value.
            @_setupValueComp key

        @_fields[key].get()

    hasKey: (key) ->
        return key of @_fields unless Tracker.active

        @_hasKeyDeps[key] ?= new Deps.Dependency()
        @_hasKeyDeps[key].depend()

        key of @_fields

    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"

    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keyFunc and AutoDict.valueFunc"

    stop: ->
        if @active
            for key of @_fields
                @_valueComps[key].stop()
            @_keysComp.stop()
            @active = false

        Tracker.nonreactive =>
            @constructor._deepStop reactiveVar.get() for key, reactiveVar of @_fields

        null

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

    replaceValueFunc: (valueFunc) ->
        @valueFunc = valueFunc
        for key, valueComp of @_valueComps
            valueComp.invalidate()

    @_deepStop = (x) ->
        if x instanceof J.AutoDict
            x.stop()
        else if _.isArray x
            @_deepStop(v) for v in x
        else if J.util.isPlainObject x
            @_deepStop(v) for k, v of x