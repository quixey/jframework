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
        J.assert key of @_fields, "Missing key #{J.util.stringify key}"

        @_stopField key

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

    _initField: (key, value) ->
        # This question mark is because a child class may have
        # already initted this.
        @_fields[key] ?= new ReactiveVar(
            @constructor._deepReactify value
            @equalsFunc
        )

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
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

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
        unless J.util.isPlainObject fields
            throw new Meteor.Error "Invalid setter: #{fields}"
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"
        if @readOnly
            throw new Meteor.Error "#{@constructor.name} is read-only"

        @_forceSet fields

    setOrAdd: (fields) ->
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

    setReadOnly: (@readOnly = true, deep = false) ->
        if deep
            @constructor._deepSetReadOnly Tracker.nonreactive => @getFields()

    size: ->
        # Reactive
        # TODO: Can make this its own finer-grained sizeDep
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
        "Dict#{J.util.stringify @getFields()}"


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

    @decodeKey: (encodedKey) ->
        ###
            encodedKey:
                A string that was outputted by @encodeKey

            Returns:
                An object which is equal to (according to J.util.equals)
                the original key.

            NOTE:
                It's unclear if it's ever good practice to call this
                function in production code. It just seems like a useful
                console thing.
        ###

        unless _.isString(encodedKey) and encodedKey.indexOf('<<KEY>>') is 0
            throw new Meteor.Error "Not an encoded key."

        preparedX = EJSON.parse encodedKey.substring '<<KEY>>'.length

        decodeModelInstances = (y) ->
            if J.util.isPlainObject(y) and _.size(y) is 1 and y.$attachedModelInstance?
                instanceSpec = y.$attachedModelInstance
                instance = J.models[instanceSpec.modelName].findOne instanceSpec.id

                # It's pretty awkward if the original instance dies
                # and then a new instance with that id takes its
                # place between encoding and decoding, but whatever.
                # Decoding a dict key seems like just something to do
                # in the console anyway.
                # This is one reason we probably shouldn't call this
                # function in production code.
                unless instance?
                    console.warn "Model instance died after being encoded."

                instance
            else if _.isArray y
                decodeModelInstances z for z in y
            else
                y

        decodeModelInstances preparedX


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
            J.List (@_deepReactify v for v in x)
        else if J.util.isPlainObject x
            fields = {}
            for key, value of x
                fields[key] = @_deepReactify value
            J.Dict fields
        else
            x

    @encodeKey: (x) ->
        ###
            Returns:
                A string which may be used as a dict key
                and later decoded back to the original
                input using @decodeKey
        ###

        prepare = (y) ->
            if _.isArray y
                prepare z for z in y
            else if y instanceof J.Model
                if y.attached and y.alive
                    $attachedModelInstance:
                        modelName: y.modelClass.name
                        _id: y._id
                else
                    throw new Meteor.Error "Only attached and alive
                        model instances are valid Dict keys"
            else if (
                _.isString(y) or _.isNumber(y) or _.isBoolean(y) or
                y is null
            )
                y
            else
                throw new Meteor.Error "Can't encode key containing: #{y}"

        "<<KEY>>#{EJSON.stringify prepare x}"