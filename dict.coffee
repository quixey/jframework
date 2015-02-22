class J.Dict
    constructor: (fieldsOrKeys, options) ->
        ###
            Options:
                creator: The computation which "created"
                    this Dict, which makes it inactive
                    when it invalidates.
                tag: A toString-able object for debugging
                onChange: function(key, oldValue, newValue) or null
                withFieldFuncs=true: Make @[fieldName]() getter/setter
        ###

        unless @ instanceof J.Dict
            return new J.Dict fieldsOrKeys, options

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        @tag = if J.debugTags then options?.tag else null

        if fieldsOrKeys?
            if fieldsOrKeys instanceof J.Dict
                fields = fieldsOrKeys.getFields()
                @tag ?=
                    constructorCloneOf: values
                    tag: "#{@constructor.name} clone of (#{values.toString()})"
            else if _.isArray fieldsOrKeys
                fields = {}
                for key in fieldsOrKeys
                    fields[key] = undefined
            else if J.util.isPlainObject fieldsOrKeys
                fields = fieldsOrKeys
            else
                throw new Meteor.Error "Invalid fieldsOrKeys: #{fieldsOrKeys}"
        else
            fields = {}

        if options?.creator is undefined
            @creator = Tracker.currentComputation
        else
            @creator = options.creator
        @onChange = options?.onChange ? null
        @withFieldFuncs = options?.withFieldFuncs ? true

        @_fields = {}
        @_keysDep = new Tracker.Dependency @creator

        @readOnly = false

        if not _.isEmpty fields
            @setOrAdd fields


    _clear: ->
        @_delete key for key of @_fields
        null


    _delete: (key) ->
        J.assert key of @_fields, "Missing key #{J.util.stringify key}"

        oldValue = Tracker.nonreactive => @_fields[key].get()
        if oldValue isnt undefined and @onChange?
            Tracker.afterFlush =>
                if @isActive()
                    @onChange.call @, key, oldValue, undefined

        delete @[key]
        delete @_fields[key]

        @_keysDep?.changed()


    _forceSet: (fields) ->
        for key, value of fields
            if key not of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set value
        null


    _get: (key, force) ->
        canGet = @isActive()
        if not canGet
            throw new Meteor.Error "Computation[#{Tracker.currentComputation?._id}]
                can't get key #{JSON.stringify key} of inactive #{@constructor.name}: #{@}"

        # The @hasKey call is necessary to reactively invalidate
        # the computation if and when this field gets added/deleted.
        # It's not at all redundant with @_fields[key].get(), which
        # invalidates the computation if and when this field gets
        # changed.
        if @hasKey key
            @_fields[key].get()
        else if force
            throw new Meteor.Error "#{@constructor.name} missing key: #{J.util.stringify key}"
        else
            undefined


    _initField: (key, value) ->
        @_fields[key] = J.Var value,
            creator: @creator
            tag:
                dict: @
                fieldKey: key
                tag: "#{@toString()}._fields[#{J.util.stringify key}]"
            onChange: @onChange?.bind(@, key) ? null

        if @withFieldFuncs then @_setupGetterSetter key

        @_keysDep?.changed()


    _replaceKeys: (newKeys) ->
        keysDiff = J.util.diffStrings _.keys(@_fields), J.List.unwrap(newKeys)
        @_delete key for key in keysDiff.deleted
        @_initField key, J.makeValueNotReadyObject() for key in keysDiff.added
        keysDiff


    _setupGetterSetter: (key) ->
        # This question mark is to avoid overshadowing members
        # like "creator" and "get".
        if key not of @
            @[key] = (v) ->
                if arguments.length is 0
                    @forceGet key
                else
                    @set key, v


    clear: ->
        @_clear()


    clone: (options = {}) ->
        # Nonreactive because a clone is its own
        # new piece of application state.
        fieldsSnapshot = Tracker.nonreactive => @getFields()
        @constructor fieldsSnapshot, _.extend(
            {
                creator: Tracker.currentComputation
                tag:
                    clonedFrom: @
                    tag: "clone of #{@toString}"
                onChange: null
            }
            options
        )


    debug: ->
        console.log @toString()
        for key, v of @_fields
            console.group key
            v?.debug()
            console.groupEnd()


    delete: (key) ->
        if key of @_fields
            @_delete key
        null


    forceGet: (key) ->
        @_get key, true


    forEach: (f) ->
        f key, value for key, value of @getFields()
        null


    get: (key) ->
        @_get key, false


    getFields: (keys = @getKeys()) ->
        keysList = J.List.wrap keys
        fields = {}
        keysList.forEach (key, i) =>
            fields[key] = @get key
        fields


    getKeys: ->
        @_keysDep.depend()
        _.keys @_fields


    getValues: ->
        _.values @getFields()


    hasKey: (key) ->
        @_keysDep.depend()
        key of @_fields


    isActive: ->
        not @creator?.invalidated


    replaceKeys: (newKeys) ->
        @_replaceKeys newKeys


    set: (fields) ->
        setter = Tracker.currentComputation
        canSet = @isActive() # or (setter? and setter is @creator)
        if not canSet
            throw new Meteor.Error "Can't set value of inactive #{@constructor.name}: #{@}"

        ret = undefined
        if not J.util.isPlainObject(fields) and arguments.length > 1
            # Support set(fieldName, value) syntax
            fieldName = fields
            value = arguments[1]
            fields = {}
            fields[fieldName] = value
            ret = value # This type of setter returns the value
        unless J.util.isPlainObject fields
            throw new Meteor.Error "Invalid setter: #{fields}"
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} is read-only"

        @_forceSet fields
        ret


    setOrAdd: (fields) ->
        setter = Tracker.currentComputation
        canSet = @isActive() # or (setter? and setter is @creator)
        if not canSet
            throw new Meteor.Error "Can't set value of inactive #{@constructor.name}: #{@}"

        ret = undefined
        if not J.util.isPlainObject(fields) and arguments.length > 1
            # Support set(fieldName, value) syntax
            fieldName = fields
            value = arguments[1]
            fields = {}
            fields[fieldName] = value
            ret = value # This type of setter returns the value
        unless J.util.isPlainObject fields
            throw new Meteor.Error "Invalid setter: #{fields}"
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"

        setters = {}
        for key, value of fields
            if key of @_fields
                setters[key] = value
            else
                @_initField key, value
        @set setters
        ret


    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @constructor._deepSetReadOnly Tracker.nonreactive => @getFields()


    size: ->
        # TODO: Finer-grained reactivity
        if not @isActive()
            throw new Meteor.Error "Can't get size of inactive #{@constructor.name}: #{@}"

        keys = @getKeys()
        if keys is undefined then undefined else keys.length


    toObj: ->
        fields = @getFields()

        obj = {}
        for key, value of fields
            if value instanceof J.Dict
                obj[key] = value.toObj()
            else if value instanceof J.List
                obj[key] = value.toArr()
            else
                obj[key] = value
        obj


    tryGet: (key) ->
        J.tryGet => @get key


    toString: ->
        s = "Dict[#{@_id}]"
        if @tag then s += "(#{J.util.stringifyTag @tag})"
        if not @isActive() then s += " (inactive)"
        s


    @_deepSetReadOnly = (x, readOnly = true) ->
        if (x instanceof J.Dict and x not instanceof J.AutoDict) or x instanceof J.List
            x.setReadOnly readOnly, true
        else if _.isArray x
            @_deepSetReadOnly(v, readOnly) for v in x
        else if J.util.isPlainObject x
            @_deepSetReadOnly(v, readOnly) for k, v of x


    @unwrap: (dictOrObj) ->
        if dictOrObj instanceof J.Dict
            dictOrObj.getFields()
        else if J.util.isPlainObject dictOrObj
            dictOrObj
        else
            throw new Meteor.Error "#{@constructor.name} can't unwrap #{dictOrObj}"


    @wrap: (dictOrObj) ->
        if dictOrObj instanceof @
            dictOrObj
        else if J.util.isPlainObject dictOrObj
            @ dictOrObj
        else
            throw new Meteor.Error "#{@constructor.name} can't wrap #{dictOrObj}"