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

        @setOrAdd fields

    _clear: ->
        @_delete key for key of @_fields
        null

    _delete: (key) ->
        if key of @_fields
            delete @[key]
        ret = delete @_fields[key]

        @constructor._deepStop Tracker.nonreactive => @get key

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

        ret

    _initField: (key, value) ->
        @_fields[key] = new ReactiveVar value, @equalsFunc

        @[key] ?= (v) ->
            if arguments.length is 0
                @get key
            else
                @set key: v

        @_keysDep.changed()
        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

    _replaceKeys: (newKeys) ->
        keysDiff = @constructor.diff @keys(), newKeys
        @_delete key for key in keysDiff.deleted
        @_initField key, undefined for key in keysDiff.added
        keysDiff

    _set: (fields) ->
        for key, value of fields
            unless key of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set value
            null

    clear: ->
        @_clear()

    delete: (key) ->
        @_delete key

    get: (key, defaultValue) ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        if key of @_fields
            # Good thing we didn't say "if @hasKey key", because having @_fields[key]
            # means we don't need @_hasKeyDeps[key].
            @_fields[key].get()

        else if arguments.length is 2
            # @_fields[key] doesn't exist to make this reactive, so we'll
            # borrow the reactivity from @hasKey.
            # @hasKey obviously returns false; we just need it to invalidate
            # the computation if and when the key ever does exist.
            # Technically we don't need to invalidate until the key exists
            # with a value other than defaultValue, but that's probably
            # too fine-grained for us to track.
            @hasKey key
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
        JSON.stringify @getObj()

    set: (fields) ->
        @_set fields

    setOrAdd: (fields) ->
        for key, value of fields
            if key of @_fields
                @_set key: value
            else
                @_initField key, value
        null

    stop: ->
        if @active
            for key, reactiveVar of @_fields
                @constructor._deepStop Tracker.nonreactive => reactiveVar.get()
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