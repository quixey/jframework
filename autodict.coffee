###
    TODO:
    1.
        this
            J.AutoDict(
                J.List [1, 2, 3] *or* [1, 2, 3]
                (key) -> f()
            )
        should be like this
            J.AutoDict(
                -> J.List [1, 2, 3]
                (key) -> f()
            )
        and have a bonus of initializing the functions .1(), .2(), .3() at construct time


    2.
        this
            J.AutoDict(
                a: -> 3
                b: -> 4
                onChange
            )
        should turn into this
            J.AutoDict(
                -> ['a', 'b']
                (k) -> {a: (-> 3), b: (-> 4)}[k]()
                onChange
            )
###



class J.AutoDict extends J.Dict
    constructor: (tag, keysFunc, valueFunc, onChange) ->
        unless @ instanceof J.AutoDict
            return new J.AutoDict tag, keysFunc, valueFunc, onChange

        if _.isFunction tag
            # Alternate signature: J.AutoDict(keysFunc, valueFunc, onChange)
            onChange = valueFunc
            valueFunc = keysFunc
            keysFunc = tag
            tag = undefined

        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        super {},
            onChange: null # doesn't support onChange=true
            tag: tag

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

        @creator = Tracker.currentComputation

        @_pendingNewKeys = null
        @_keysVar = J.AutoVar(
            (
                autoDict: @
                tag: "#{@toString()} keysVar"
            )

            =>
                keys = @keysFunc.apply null

                unless _.isArray(keys) or keys instanceof J.List
                    throw "AutoDict.keysFunc must return an array or List.
                        Got #{J.util.stringify keys}"

                keysArr = J.List.unwrap(keys)

                unless _.all (_.isString(key) for key in keysArr)
                    throw new Meteor.Error "AutoDict keys must all be type string.
                        Got #{J.util.stringify keys}"
                if _.size(J.util.makeDictSet keysArr) < keys.length
                    throw new Meteor.Error "AutoDict keys must be unique."

                @_pendingNewKeys = keys # Without toArr, this wont be invalidated much

                # Would be better to return the keys list itself, but then
                # we need a call like .observe to listen for changes, since
                # the list pointer might not change when its contents do.
                keysArr

            (oldKeys, newKeys) =>
                ###
                    The naive implementation is @_replaceKeys(newKeys), but this has
                    two problems:
                    1. @_keysVar might queue up multiple change events before the flush,
                       and it's wasteful to @_replaceKeys a bunch of times.
                    2. Even worse, @get() may have been called on a new key, which
                       would cause _initField to be called before the flush, and now
                       we can only trust the last call to this onChange function,
                       otherwise @_replaceKeys(newKeys) might actually revert the keys
                       back to an earlier state and kill the field's AutoVar.
                ###
                if @_pendingNewKeys?
                    @_replaceKeys @_pendingNewKeys
                    @_pendingNewKeys = null

            creator: @creator
        )

        @_active = true
        if Tracker.active
            Tracker.onInvalidate => @stop()


    _delete: (key) ->
        oldValue = @_fields[key]._var._previousReadyValue
        @_fields[key].stop()

        if oldValue isnt undefined and _.isFunction @onChange
            Tracker.afterFlush J.bindEnvironment =>
                if @isActive()
                    @onChange.call @, key, oldValue, undefined

        super


    _get: (key, force) ->
        if @hasKey key
            if key not of @_fields
                # Key would have been initialized at Tracker.afterFlush time
                @_initField key
            @_fields[key].get()
        else if force
            throw new Meteor.Error "#{@constructor.name} missing key #{J.util.stringify key}"
        else
            undefined


    _initField: (key) ->
        @_fields[key] = J.AutoVar(
            (
                autoDict: @
                fieldKey: key
                tag: "#{@toString()}._fields[#{J.util.stringify key}]"
            )

            => @valueFunc.call null, key, @

            if _.isFunction @onChange
                (oldValue, newValue) => @onChange.call @, key, oldValue, newValue
            else
                @onChange

            creator: @creator
        )

        super


    clear: ->
        throw new Meteor.Error "There is no AutoDict.clear"


    clone: ->
        throw new Meteor.Error "There is no AutoDict.clone.
            You should be able to either use the same AutoDict
            or else call snapshot()."

    delete: ->
        throw new Meteor.Error "There is no AutoDict.delete"


    forceGet: (key) ->
        unless @isActive()
            @logDebugInfo()
            throw new Meteor.Error "AutoDict(#{@tag ? ''}) is stopped.
                Current computation: #{Tracker.currentComputation?.tag}"
        super


    getKeys: ->
        @_keysVar.get().getValues()


    hasKey: (key) ->
        @_keysVar.get().contains key


    isActive: ->
        @_active


    replaceKeys: ->
        throw new Meteor.Error "There is no AutoDict.replaceKeys; use AutoDict.replaceKeysFunc"


    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"


    setDebug: (@debug) ->


    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keysFunc and AutoDict.valueFunc"


    snapshot: ->
        keys = Tracker.nonreactive => @getKeys()
        if keys is undefined
            undefined
        else
            J.Dict Tracker.nonreactive => @getFields()


    stop: ->
        if @_active
            @_keysVar.stop()
            @_fields[key].stop() for key of @_fields
            @_active = false


    toString: ->
        s = "AutoDict[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s