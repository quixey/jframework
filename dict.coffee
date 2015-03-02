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
                fineGrained=true: Fine-grained reactivity. Takes more
                    memory but doesn't invalidate unnecessarily.
        ###

        unless @ instanceof J.Dict and not @_id?
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
        @fineGrained = options?.fineGrained ? true
        @withFieldFuncs = options?.withFieldFuncs ? true

        # fineGrained=true stuff
        @_fields = if @fineGrained then {} else null
        @_keysDep = if @fineGrained then new Tracker.Dependency @creator else null

        # fineGrained=false stuff
        @_fieldsVar = if @fineGrained then null else
            J.Var(
                {}

                tag:
                    dict: @
                    tag: "#{@} fieldsVar"
                creator: @creator
                wrap: false
                onChange:
                    if _.isFunction @onChange
                        (oldFields, newFields) =>
                            keysDiff = J.util.diffStrings _.keys(oldFields), _.keys(newFields)
                            for key in keysDiff.deleted
                                @onChange key, oldFields[key], undefined
                            for key in keysDiff.added
                                @onChange key, undefined, newFields[key]
            )

        @readOnly = false

        if not _.isEmpty fields then @setOrAdd fields


    _clear: ->
        @_delete key for key of @_fields
        null


    _delete: (key) ->
        J.assert key of @_fields, "Missing key #{J.util.stringify key}"

        if @fineGrained
            oldValue = Tracker.nonreactive => @_get key
            if oldValue isnt undefined and @onChange?
                Tracker.afterFlush =>
                    if @isActive()
                        @onChange.call @, key, oldValue, undefined

            delete @_fields[key]
            @_keysDep?.changed()

        else
            fields = _.clone @_fieldsVar.get()
            delete fields[key]
            @_fieldsVar.set fields

        delete @[key]

    _forceSet: (fields) ->
        if @fineGrained
            for key, value of fields
                if key not of @_fields
                    throw new Meteor.Error "Field #{JSON.stringify key} does not exist"

                if @_fields[key] not instanceof J.Var
                    # We need a Var to set this object up to invalidate getters
                    # when its creator invalidates.
                    if (
                        value instanceof J.List or value instanceof J.Dict or
                        _.isArray(value) or J.util.isPlainObject(value) or
                        value instanceof J.VALUE_NOT_READY
                    )
                        @_initFieldVar key

                if @_fields[key] instanceof J.Var
                    @_fields[key].set value
                else
                    @_fields[key] = value

        else
            newFields = _.clone @_fieldsVar.get()
            for key, value of fields
                if key not of newFields
                    throw new Meteor.Error "Field #{JSON.stringify key} does not exist"
                newFields[key] = J.Var.wrap value, @withFieldFuncs
            @_fieldsVar.set newFields

        null


    _get: (key, force) ->
        if not @isActive()
            throw new Meteor.Error "Computation[#{Tracker.currentComputation?._id}]
                can't get key #{JSON.stringify key} of inactive #{@constructor.name}: #{@}"

        if @fineGrained
            # The @hasKey call is necessary to reactively invalidate
            # the computation if and when this field gets added/deleted.
            # It's not at all redundant with @_fields[key].get(), which
            # invalidates the computation if and when this field gets
            # changed.
            if @hasKey key
                unless @_fields[key] instanceof J.Var or @_fields[key] instanceof J.AutoVar
                    @_initFieldVar key
                @_fields[key].get()
            else if force
                throw new Meteor.Error "#{@constructor.name} missing key: #{J.util.stringify key}"
            else
                undefined
        else
            fields = @_fieldsVar.get()
            if key of fields
                J.Var(fields[key]).get()
            else
                undefined


    _initFieldVar: (key) ->
        @_fields[key] = J.Var @_fields[key],
            creator: @creator
            tag:
                dict: @
                fieldKey: key
                tag: "#{@toString()}._fields[#{J.util.stringify key}]"
            onChange: if _.isFunction(@onChange) then @onChange.bind(@, key) else null


    _initField: (key, value) ->
        if @fineGrained
            @_fields[key] = value
            if (
                _.isFunction(@onChange) or
                value instanceof J.List or value instanceof J.Dict or
                _.isArray(value) or J.util.isPlainObject(value) or
                value instanceof J.VALUE_NOT_READY
            )
                # We need a Var to set this object up to invalidate getters
                # when its creator invalidates.
                @_initFieldVar key

            @_keysDep?.changed()

        else
            fields = _.clone @_fieldsVar.get()
            fields[key] = J.Var.wrap value, @withFieldFuncs
            @_fieldsVar.set fields

        if @withFieldFuncs then @_setupGetterSetter key


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
        for key, v of @_fields ? @_fieldsVar._value
            console.group key
            v?.debug()
            console.groupEnd()


    deepClone: (options = {}) ->
        objSnapshot = Tracker.nonreactive => @toObj()
        @constructor objSnapshot, _.extend(
            {
                creator: Tracker.currentComputation
                tag:
                    deepClonedFrom: @
                    tag: "deep clone of #{@toString}"
                onChange: null
            }
            options
        )


    delete: (key) ->
        if Tracker.nonreactive(=> @hasKey key)
            @_delete key
        null


    forceGet: (key) ->
        @_get key, true


    forEach: (f) ->
        # Returns an array
        f key, value for key, value of @getFields()


    get: (key) ->
        @_get key, false


    getFields: (keys = @getKeys()) ->
        keysArr = J.List.unwrap keys
        fields = {}
        if @fineGrained
            for key in keysArr
                fields[key] = @get key
        else
            allFields = @_fieldsVar.get()
            for key in keysArr
                fields[key] = allFields[key]
        fields


    getKeys: ->
        if @fineGrained
            @_keysDep?.depend()
            _.keys @_fields
        else
            _.keys @_fieldsVar.get()


    getValues: ->
        _.values @getFields()


    hasKey: (key) ->
        if @fineGrained
            @_keysDep.depend()
            key of @_fields
        else
            key of @_fieldsVar.get()


    isActive: ->
        not @creator?.invalidated


    set: (fields) ->
        setter = Tracker.currentComputation
        if not @isActive()
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
        if not @isActive()
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
            if Tracker.nonreactive(=> @hasKey key)
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


    tryGet: (key, defaultValue) ->
        J.tryGet(
            => @get key
            defaultValue
        )


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