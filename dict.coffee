class J.Dict
    constructor: (fieldsOrKeys, equalsFunc = J.util.equals) ->
        unless @ instanceof J.Dict
            return new J.Dict fieldsOrKeys, equalsFunc

        @equalsFunc = equalsFunc

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

        @_creatorComp = Tracker.currentComputation

        @_fields = {}
        @_hasKeyDeps = {} # realOrImaginedKey: Dependency
        @_keysDep = new J.Dependency @_creatorComp

        @readOnly = false

        @setOrAdd fields unless _.isEmpty fields

    _clear: ->
        @_delete key for key of @_fields
        null

    _delete: (key) ->
        J.assert key of @_fields, "Missing key #{J.util.stringify key}"

        delete @[key]
        delete @_fields[key]

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _forceSet: (fields) ->
        for key, value of fields
            if key not of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set @constructor._deepReactify value
        null

    _get: (key, force) ->
        # The @hasKey call is necessary to reactively invalidate
        # the computation if and when this field gets added/deleted.
        # It's not at all redundant with @_fields[key].get(), which
        # invalidates the computation if and when this field gets
        # changed.
        if @hasKey key
            value = @_fields[key].get()
            if value instanceof J.AutoVar then value.get() else value
        else if force
            throw new Meteor.Error "#{@constructor.name} missing key: #{J.util.stringify key}"
        else
            undefined

    _initField: (key, value) ->
        # This question mark is because a child class may have
        # already initted this.
        @_fields[key] ?= new ReactiveVar(
            @constructor._deepReactify value
            @equalsFunc
        )

        # FIXME: We really need our own J.ReactiveVar class, instead
        # of hacking the .dep field of Meteor's ReactiveVar
        @_fields[key].dep = new J.Dependency @_creatorComp

        # This question mark is to avoid overshadowing reserved
        # members like "set".
        @[key] ?= (v) ->
            if arguments.length is 0
                @forceGet key
            else
                @set key, v

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _replaceKeys: (newKeys) ->
        keysDiff = @constructor.diff _.keys(@_fields), newKeys
        @_delete key for key in keysDiff.deleted
        @_initField key, undefined for key in keysDiff.added
        keysDiff

    clear: ->
        @_clear()

    clone: ->
        # Nonreactive because a clone is its own
        # new piece of application state.
        @constructor Tracker.nonreactive => @getFields()

    delete: (key) ->
        if key of @_fields
            @_delete key
        null

    forceGet: (key) ->
        # Reactive
        @_get key, true

    forEach: (f) ->
        # Reactive
        f key, value for key, value of @getFields()
        null

    get: (key) ->
        # Reactive
        @_get key, false

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
            @_hasKeyDeps[key] ?= new J.Dependency @_creatorComp
            @_hasKeyDeps[key].depend()

        key of @_fields

    replaceKeys: (newKeys) ->
        @_replaceKeys newKeys

    set: (fields) ->
        ret = undefined
        if not J.util.isPlainObject(fields) and arguments.length > 1
            # Support set(fieldName, value) syntax
            fieldName = fields
            value = arguments[1]
            fields = {}
            fields[fieldName] = value
            ret = value # This type of setter returns the value too
        unless J.util.isPlainObject fields
            throw new Meteor.Error "Invalid setter: #{fields}"
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} is read-only"

        @_forceSet fields
        ret

    setOrAdd: (fields) ->
        ret = undefined
        if not J.util.isPlainObject(fields) and arguments.length > 1
            # Support set(fieldName, value) syntax
            fieldName = fields
            value = arguments[1]
            fields = {}
            fields[fieldName] = value
            ret = value # This type of setter returns the value too
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
        # Reactive
        @getKeys().length

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
        "Dict#{J.util.stringify @getFields()}"


    @_deepSetReadOnly = (x, readOnly = true) ->
        if (x instanceof J.Dict and x not instanceof J.AutoDict) or x instanceof J.List
            x.setReadOnly readOnly, true
        else if _.isArray x
            @_deepSetReadOnly(v, readOnly) for v in x
        else if J.util.isPlainObject x
            @_deepSetReadOnly(v, readOnly) for k, v of x


    @diff: (arrA, arrB) ->
        unless _.all(_.isString(x) for x in arrA) and _.all(_.isString(x) for x in arrB)
            throw new Meteor.Error "Dict.diff only works on arrays of strings."

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
            J.List (@_deepReactify v for v in x)
        else if J.util.isPlainObject x
            fields = {}
            for key, value of x
                fields[key] = @_deepReactify value
            J.Dict fields
        else
            x
