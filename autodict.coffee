class J.AutoDict extends J.Dict
    constructor: (tag, keysFunc, valueFunc, onChange) ->
        ###
            Overloads
            (1) J.AutoDict [tag], keysFunc, valueFunc, [onChange]
            (2) J.AutoDict [tag], keysList, valueFunc, [onChange]
            (3) J.AutoDict [tag], fieldSpecs, [onChange]
        ###

        unless @ instanceof J.AutoDict
            return new J.AutoDict tag, keysFunc, valueFunc, onChange

        # Reshuffle arguments to make overloads work. We can just
        # convert everything to (tag, keysFunc, valueFunc, onChange).

        if (
            _.isFunction(tag) or
            _.isArray(tag) or tag instanceof J.List or
            (
                (J.util.isPlainObject(tag) or tag instanceof J.Dict) and
                (not keysFunc? or _.isFunction(keysFunc)) and not valueFunc?
            )
        )
            # tag argument not provided
            onChange = valueFunc
            valueFunc = keysFunc
            keysFunc = tag
            tag = undefined

        if _.isArray(keysFunc) or keysFunc instanceof J.List
            # Overload (2) -> (1)
            @_keysList = J.List.wrap keysFunc
            keysFunc = => @_keysList

        else if J.util.isPlainObject(keysFunc) or keysFunc instanceof J.Dict
            # Overload (3) -> (1)
            @_fieldSpecs = J.Dict.wrap keysFunc
            @_setupGetterSetter key for key of @_fieldSpecs
            onChange = valueFunc
            keysFunc = => @_fieldSpecs.getKeys()
            valueFunc = (key) =>
                v = @_fieldSpecs.forceGet key
                if _.isFunction v then v(key) else v


        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with
                keysFunc and valueFunc"

        super {},
            creator: Tracker.currentComputation
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

        @_pendingNewKeys = null
        @_keysVar = J.AutoVar(
            (
                autoDict: @
                tag: "#{@toString()} keysVar"
            )

            =>
                keys = @keysFunc.apply null

                unless _.isArray(keys) or keys instanceof J.List
                    throw new Meteor.Error "AutoDict.keysFunc must return a List
                        or array. Got #{J.util.stringify keys}"

                keysArr = J.List.unwrap(keys)

                unless _.all (_.isString(key) for key in keysArr)
                    throw new Meteor.Error "AutoDict keys must all be type string.
                        Got #{J.util.stringify keys}"
                if _.size(J.util.makeDictSet keysArr) < keys.length
                    throw new Meteor.Error "AutoDict keys must be unique."

                # Side effects during AutoVar recompute functions are usually not okay.
                # We just need the framework to do it in this one place.
                @_replaceKeys keys

                keys

            if @onChange? then true else null

            creator: @creator
        )

        @_active = true
        if Tracker.active
            Tracker.onInvalidate =>
                # console.log 'INVALIDATED', @toString()
                @stop()

        if @_keysList?
            @_keysList.forEach (key) => @_setupGetterSetter key
        else if @_fieldSpecs?
            @_fieldSpecs.getKeys().forEach (key) => @_setupGetterSetter key


    _delete: (key) ->
        fieldAutoVar = @_fields[key]
        super
        fieldAutoVar.stop()


    _get: (key, force) ->
        hasKey = @hasKey key
        return undefined if hasKey is undefined

        if hasKey
            @_fields[key].get()
        else
            if force
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

            =>
                # If @_keysVar needs recomputing, this @hasKey call will throw
                # a COMPUTING. Then this field-autovar may or may not be left
                # standing to recompute and continue past the assert.
                J.assert @hasKey key

                @valueFunc.call null, key, @

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


    getFields: (keys = @getKeys()) ->
        if keys is undefined
            undefined
        else
            super keys


    getKeys: ->
        @_keysVar.get()?.getValues()


    hasKey: (key) ->
        if @_keysVar.currentValueMightChange()
            # This might have a special @_replaceKeys side effect
            # which then makes the logic in super work
            keysList = Tracker.nonreactive => @_keysVar.get()
            if keysList is undefined
                if Tracker.active then throw J.AutoVar.makeComputingObject()
                else return undefined
        super


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
            # console.log "STOPPING", @toString()
            fieldComp.stop() for key, fieldComp of @_fields
            @_keysVar.stop()
            @_active = false


    toString: ->
        s = "AutoDict[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s