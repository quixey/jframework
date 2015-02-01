class J.Dict
    constructor: (fieldsOrKeys, @equalsFunc = J.util.equals) ->
        if fieldsOrKeys?
            if _.isArray fieldsOrKeys
                fields = {}
                for key in fieldsOrKeys
                    fields[key] = undefined
            else if J.util.isPlainObject fieldsOrKeys
                fields = fieldsOrKeys
            else
                throw new Meteor.Error "Invalid fieldsOrKeys"
        else
            fields = {}

        @_fields = {}
        @_hasKeyDeps = {} # realOrImaginedKey: Dependency
        @_keysDep = new Deps.Dependency()

        @active = true
        @readOnly = false

        @setOrAdd fields unless _.isEmpty fields

    _clear: ->
        @_delete key for key of @_fields
        null

    _delete: (key) ->
        J.assert key of @_fields, "Missing key #{J.util.toString key}"

        @_stopField key

        delete @[key]
        delete @_fields[key]

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _initField: (key, value) ->
        # This question mark is because a child class may have
        # already initted this.
        @_fields[key] ?= new ReactiveVar value, @equalsFunc

        # This question mark is to avoid overshadowing reserved
        # members like "set".
        @[key] ?= (v) ->
            if arguments.length is 0
                @forceGet key
            else
                setter = {}
                setter[key] = v
                @set setter

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _replaceKeys: (newKeys) ->
        keysDiff = @constructor.diff _.keys(@_fields), newKeys
        @_delete key for key in keysDiff.deleted
        @_initField key, undefined for key in keysDiff.added
        keysDiff

    _stopField: (key) ->
        @constructor._deepStop Tracker.nonreactive => @_fields[key].get()

    clear: ->
        @_clear()

    delete: (key) ->
        if key of @_fields
            @_delete key
        null

    _forceSet: (fields) ->
        for key, value of fields
            if key not of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set @constructor._deepReactify value
        null

    forceGet: (key) ->
        if @hasKey key
            @_fields[key].get()
        else
            throw new Meteor.Error "#{@constructor.name} missing key #{JSON.stringify key}"

    get: (key, defaultValue = undefined) ->
        # Reactive
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        # The @hasKey call is necessary to reactively invalidate
        # the computation if and when this field gets added/deleted.
        # It's not at all redundant with @_fields[key].get(), which
        # invalidates the computation if and when this field gets
        # changed.
        if @hasKey key
            @_fields[key].get()
        else
            defaultValue

    getFields: (keys = @getKeys()) ->
        # Reactive
        fields = {}
        for key in keys
            fields[key] = @get key
        fields

    getKeys: ->
        # Reactive
        @_keysDep.depend()
        _.keys @_fields

    getValues: ->
        # Reactive
        _.values @getFields()

    hasKey: (key) ->
        # Reactive
        if Tracker.active
            @_hasKeyDeps[key] ?= new Deps.Dependency()
            @_hasKeyDeps[key].depend()

        key of @_fields

    replaceKeys: (newKeys) ->
        @_replaceKeys newKeys

    set: (fields) ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} is read-only"

        @_forceSet fields

    setOrAdd: (fields) ->
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} instance is read-only"

        setters = {}
        for key, value of fields
            if key of @_fields
                setters[key] = value
            else
                @_initField key, value
        @set setters

    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @constructor._deepSetReadOnly Tracker.nonreactive => @getFields()

    size: ->
        # Reactive
        @getKeys().length

    stop: ->
        if @active
            @_stopField key for key of @_fields
            @active = false
        null

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

    toString: ->
        # Reactive
        J.util.toString @toObj()


    @_deepSetReadOnly = (x, readOnly = true) ->
        if (x instanceof J.Dict and x not instanceof J.AutoDict) or x instanceof J.List
            x.setReadOnly readOnly, true
        else if _.isArray x
            @_deepSetReadOnly(v, readOnly) for v in x
        else if J.util.isPlainObject x
            @_deepSetReadOnly(v, readOnly) for k, v of x

    @_deepStop = (x) ->
        if x instanceof J.Dict or x instanceof J.List or x instanceof J.AutoVar
            x.stop()
        else if _.isArray x
            @_deepStop(v) for v in x
        else if J.util.isPlainObject x
            @_deepStop(v) for k, v of x

    @diff: (arrA, arrB) ->
        setA = J.util.makeDictSet arrA
        setB = J.util.makeDictSet arrB
        added: _.filter arrB, (x) -> x not of setA
        deleted: _.filter arrA, (x) -> x not of setB

    @fromDeepObj: (obj) ->
        unless J.util.isPlainObject obj
            throw new Meteor.Error "Expected a plain object"

        @fromDeepObjOrArr obj

    @fromDeepObjOrArr: (x) ->
        unless _.isArray(x) or J.util.isPlainObject(x)
            throw new Meteor.Error "Expected an array or plain object"

        @_deepReactify x

    @_deepReactify: (x) ->
        if _.isArray x
            new J.List (@_deepReactify v for v in x)
        else if J.util.isPlainObject x
            fields = {}
            for key, value of x
                fields[key] = @_deepReactify value
            new J.Dict fields
        else
            x