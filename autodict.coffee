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
    constructor: (keysFunc, valueFunc, onChange = null, equalsFunc = J.util.equals, tag) ->
        unless @ instanceof J.AutoDict
            return new J.AutoDict keysFunc, valueFunc, onChange, equalsFunc, tag

        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with keysFunc and valueFunc"

        @_id = J.AutoVar._nextId
        J.AutoVar._nextId += 1
        J.AutoVar._byId[@_id] = @

        super {}, equalsFunc

        @keysFunc = keysFunc
        @valueFunc = valueFunc
        @tag = tag

        ###
            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoDict becomes non-lazy.
        ###
        @onChange = onChange

        @_pendingNewKeys = null

        @_keysVar = Tracker.nonreactive => J.AutoVar "AutoDict(#{@tag ? ''},#{@_id})._keysVar",
            ((kv) =>
                kv._valueComp.onInvalidate ->
                    console.groupCollapsed("INVALIDATED KEYSVAR: ", kv.tag, kv._id)
                    console.trace()
                    console.groupEnd()

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

                @_pendingNewKeys = newKeys

                newKeys
            ),
            ((oldKeys, newKeys) =>
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
            ),
            J.util.equals,
            false

        @active = true
        if Tracker.active then Tracker.onInvalidate =>
            console.log @tag, "GONNA STOP thanks to", @_creatorComp.tag
            @stop()

    _delete: (key) ->
        oldValue = Tracker.nonreactive => @_fields[key].get()
        @_fields[key].stop()
        if _.isFunction @onChange then Tracker.afterFlush =>
            @onChange.call @, key, oldValue, undefined
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
        @_fields[key] = Tracker.nonreactive => J.AutoVar "AutoDict(#{@tag ? ''})._fields[#{J.util.stringify key}]",
            =>
                # In the AutoVar graph, set up the dependency
                # @_keysVar -> @_fields[key]
                if @hasKey key
                    @valueFunc.call null, key
                else
                    # @_delete(key) should be called during
                    # @_keysVar.onChange after flush
                    J.AutoVar._UNDEFINED_WITHOUT_SET
            ,
                if _.isFunction @onChange then (oldValue, newValue) =>
                    @onChange?.call @, key, oldValue, newValue
                else
                    @onChange
            ,
            @equalsFunc

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
        unless @active
            @logDebugInfo()
            throw new Meteor.Error "AutoDict(#{@tag ? ''}) is stopped.
                Current computation: #{Tracker.currentComputation?.tag}"
        super

    get: (key) ->
        unless @active
            @logDebugInfo()
            throw new Meteor.Error "AutoDict(#{@tag ? ''}) is stopped.
                Current computation: #{Tracker.currentComputation?.tag}"
        super

    getKeys: ->
        @_keysVar.get()

    hasKey: (key) ->
        key in @getKeys() # FIXME: Use separate deps per key

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
        # console.log "STOPPING (#{@tag}) created by (#{@_creatorComp?.tag})"
        if @active
            @_keysVar.stop()
            @_fields[key].stop() for key of @_fields
            @active = false

    logDebugInfo: ->
        if @active
            console.groupCollapsed @toString()
        else
            console.groupCollapsed "AutoDict(#{@_id}) fields=", @_fields
        @_keysVar.logDebugInfo()
        for key, fieldVar of @_fields
            fieldVar.logDebugInfo()
        console.groupEnd()

    toString: ->
        # Reactive
        objString =
            if @active
                J.util.stringify @toObj()
            else
                "STOPPED"
        "AutoDict(#{@tag ? ''},#{@_id})=#{objString}"