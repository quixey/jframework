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
                @get key
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

    get: (key, defaultValue) ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        # The @hasKey call is necessary to reactively invalidate
        # the computation if and when this field gets added/deleted.
        # It's not at all redundant with @_fields[key].get(), which
        # invalidates the computation if and when this field gets
        # changed.
        if @hasKey key
            @_fields[key].get()

        else if arguments.length is 2
            defaultValue

        else
            throw new Meteor.Error "#{@constructor.name} missing key #{JSON.stringify key}"

    getObj: (keys = @keys()) ->
        obj = {}
        for key in keys
            obj[key] = @get key
        obj

    hasKey: (key) ->
        if Tracker.active
            @_hasKeyDeps[key] ?= new Deps.Dependency()
            @_hasKeyDeps[key].depend()

        key of @_fields

    keys: ->
        if Tracker.active
            @_keysDep.depend()

        _.keys @_fields

    replaceKeys: (newKeys) ->
        @_replaceKeys newKeys

    toString: ->
        J.util.toString @getObj()

    set: (fields) ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        for key, value of fields
            if key not of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set value
        null

    setOrAdd: (fields) ->
        setters = {}
        for key, value of fields
            if key of @_fields
                setters[key] = value
            else
                @_initField key, value
        @set setters

    stop: ->
        if @active
            @_stopField key for key of @_fields
            @active = false
        null

    values: ->
        _.values @getObj()


    @_deepStop = (x) ->
        if x instanceof J.Dict or x instanceof J.AutoVar
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