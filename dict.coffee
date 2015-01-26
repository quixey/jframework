class J.Dict
    constructor: (fieldsOrKeys) ->
        if fieldsOrKeys?
            if _.isArray fieldsOrKeys
                fields = {}
                for key in fieldsOrKeys
                    fields[key] = undefined
            else if J.util.isPlainObject fieldsOrKeys
                fields = fieldsOrKeys
            else
                throw new Meteor.Erro "Invalid fieldsOrKeys"
        else
            fields = {}

        @_fields = {}
        @setOrAdd fields

    _initField: (key, value) ->
        @_fields[key] = new ReactiveVar value, J.util.equals
        @[key] = (v) ->
            if arguments.length is 0
                # Getter
                @_fields[key].get()
            else
                # Setter
                @_fields[key].set v
                null

    clear: ->
        for key of @_fields
            @delete key

    delete: (key) ->
        if key of @_fields
            delete @[key]
        delete @_fields[key]

    get: (key, defaultValue) ->
        unless @hasKey(key)
            if arguments.length >= 2
                return defaultValue
            else
                throw new Meteor.Error "Dict missing key #{JSON.stringify key}"

        @_fields[key].get()

    getObj: (keys = @keys()) ->
        obj = {}
        for key in keys
            obj[key] = @get key
        obj

    hasKey: (key) ->
        key of @_fields

    keys: ->
        _.keys @_fields

    replaceKeys: (newKeys) ->
        keysDiff = @constructor.diff @keys(), newKeys
        @delete key for key in keysDiff.deleted
        @_initField key, undefined for key in keysDiff.added
        keysDiff

    toString: ->
        JSON.stringify @getObj()

    set: (fields) ->
        for key, value of fields
            unless key of @_fields
                throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
            @_fields[key].set value
        null

    setOrAdd: (fields) ->
        for key, value of fields
            if key of @_fields
                @_fields[key].set value
            else
                @_initField key, value
        null

    @diff: (arrA, arrB) ->
        setA = J.util.makeDictSet arrA
        setB = J.util.makeDictSet arrB
        added: _.filter arrB, (x) -> x not of setA
        deleted: _.filter arrA, (x) -> x not of setB