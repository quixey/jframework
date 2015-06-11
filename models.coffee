# Copyright 2015, Quixey Inc.
# All rights reserved.
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


# FIXME:
# 1. If modelInstance has some fetched fields but modelInstance.a isn't one of them,
#    then calling modelInstance.a() should register a dependency on a query for that
#    field. Right now it just throws VALUE_NOT_READY and never does anything about it.
#
# TODO:
# 1. Let fieldSpecs have default values for fields, applicable when using "new"
# 2. A special method like modelInstance.isValid() to prevent inserting/updating an
#    invalid model
# 3. Type system with support for nested data structure schemas
# 4. Server-side read/write security specs
# 5. The field selector in a query should let you select names of reactives too,
#    and make the server compute their value
# 6. The field selector in a query should be more like GraphQL, so you can make the
#    server follow foreign keys for you without making an extra round trip.


class J.Model
    @_getEscapedSubdoc: (subDoc) ->
        if J.util.isPlainObject subDoc
            ret = {}
            for key, value of subDoc
                ret[@escapeDot key] = @_getEscapedSubdoc value
            ret
        else if _.isArray subDoc
            @_getEscapedSubdoc x for x in subDoc
        else
            subDoc


    @_getUnescapedSubdoc: (subDoc) ->
        if J.util.isPlainObject subDoc
            ret = {}
            for key, value of subDoc
                ret[@unescapeDot key] = @_getUnescapedSubdoc value
            ret
        else if _.isArray subDoc
            @_getUnescapedSubdoc x for x in subDoc
        else
            subDoc


    # ## @escapeDot
    # - - -
    # Specifically escape `.` and `$` in a string by
    # replacing them with `*DOT*` and `*DOLLAR*` respectively.
    #
    #     J.Model.escapeDot('func://www.example.com/func')
    #     # "func://www*DOT*example*DOT*.com/func"
    # - - -
    @escapeDot: (key) ->
        key.replace(/\./g, '*DOT*').replace(/\$/g, '*DOLLAR*')


    # ## @fromJSONValue
    # - - -
    # Return a new model instance with the fields set to a given JSON.
    # The input is *not* of the form `{$type: ThisModelName, $value: someValue}`.
    # It's just the `someValue` part.
    # - - -
    @fromJSONValue: (jsonValue) ->

        unless J.util.isPlainObject jsonValue
            throw new Meteor.Error 'Must override J.Model.fromJSONValue to decode non-object values'

        for fieldName, value of jsonValue
            if fieldName[0] is '$'
                throw new Meteor.Error "Bad jsonValue for #{@name}: #{jsonValue}"

        @fromDoc jsonValue


    # ## @fromDoc
    # - - -
    # Return a new model instance with the fields set
    # to the corresponding fields of a given document.
    # - - -
    @fromDoc: (doc) ->
        fields = EJSON.fromJSONValue @_getUnescapedSubdoc doc

        for fieldName of @fieldSpecs
            if fieldName not of fields
                fields[fieldName] = J.makeValueNotReadyObject()

        new @ fields

    # ## @toSubdoc
    # - - -
    # TODO: write documentation
    #
    # - - -
    @toSubdoc: (x) ->
        helper = (value) =>
            if value instanceof J.Dict
                helper value.getFields()
            else if value instanceof J.List
                helper value.getValues()
            if _.isArray(value)
                (helper v for v in value)
            else if J.util.isPlainObject(value)
                ret = {}
                for k, v of value
                    ret[@escapeDot k] = helper v
                ret
            else if value instanceof J.Model
                value.toDoc()
            else if (
                _.isNumber(value) or _.isBoolean(value) or _.isString(value) or
                    value instanceof Date or value instanceof RegExp or
                    value is null or value is undefined
            )
                value
            else
                throw new Meteor.Error "Unsupported value type: #{value}"

        helper x


    # ## @unescapeDot
    # - - -
    # Reverse the behavior of **@escapeDot**.
    # Specifically unescape `*DOT*` and `*DOLLAR*` in a string by
    # replacing them with `.` and `$` respectively.
    #
    #     J.Model.unescapeDot('func://www*DOT*example*DOT*.com/func')
    #     # "func://www.example.com/func"
    # - - -
    @unescapeDot: (key) =>
        key.replace(/\*DOT\*/g, '.').replace(/\*DOLLAR\*/g, '$')


    _save: (upsert, options, callback) ->
        collection = options.collection ? @collection
        unless collection instanceof Mongo.Collection
            throw new Meteor.Error "Invalid collection to #{@modelClass.name}.save"

        if @attached and @collection is collection
            throw new Meteor.Error "Can't save #{@modelClass.name} instance into its own attached collection"

        unless @alive
            throw new Meteor.Error "Can't save dead #{@modelClass.name} instance"

        doc = Tracker.nonreactive => @toDoc()

        if @modelClass.idSpec is J.PropTypes.key and not doc._id?
            key = @key()
            if not key?
                throw new Error "<#{@modelClass.name}>.key() returned #{key}"
            doc._id = key
        else
            doc._id = @_id ? Random.hexString(10)

        if Meteor.isClient
            options = _.clone options
            delete options.collection
            delete options.denormCallback

        Meteor.call '_jSave', @modelClass.name, doc, upsert, options, callback

        # Returns @_id
        @_id ?= doc._id


    _setReactives: (reactivesObj) ->
        # reactivesObj:
        #     The _reactives field from the raw Mongo doc,
        #     filtered down to only the denormed reactives
        #     we cared to fetch.

        reactivesSetter = {}

        for reactiveName, reactiveSpec of @modelClass.reactiveSpecs
            if reactiveSpec.denorm
                if reactiveName of reactivesObj and (
                    Meteor.isClient or reactivesObj[reactiveName].dirty is false
                )
                    reactivesSetter[reactiveName] =
                        @modelClass._getUnescapedSubdoc reactivesObj[reactiveName].val
                if reactivesSetter[reactiveName] is undefined
                    reactivesSetter[reactiveName] = J.makeValueNotReadyObject()

        @_reactives._forceSet reactivesSetter


    # ## clone
    # - - -
    # Clone a model instance. The clone is
    # nonreactive because its fields are
    # a new piece of application state.
    # Note that clones are always detached, alive, and not read-only.
    #
    #     foo = $$.Foo.fetchOne()
    #     foo.bar(42)
    #     foo.save() # Error: Cannot save attached instance.
    #     fooClone = foo.clone()
    #     fooClone.save()
    # - - -
    clone: ->
        doc = Tracker.nonreactive => @toDoc()
        for fieldName in _.keys doc
            if doc[fieldName] is undefined
                delete doc[fieldName]
        instance = @modelClass.fromDoc doc
        instance.collection = @collection
        instance


    # ## get
    # - - -
    # Get the value of a field or reactive of a model instance.
    # - - -
    get: (fieldOrReactiveName) ->
        if not @alive
            throw new Meteor.Error "#{@modelClass.name} ##{@_id} from collection #{@collection} is dead"

        isReactive = fieldOrReactiveName of @modelClass.reactiveSpecs

        if isReactive
            reactiveName = fieldOrReactiveName
            reactiveSpec = @modelClass.reactiveSpecs[fieldOrReactiveName]

            if Meteor.isServer
                if reactiveSpec.denorm
                    J.assert @_id?

                    if J._watchedQuerySpecSet.get()?
                        projection = _: false
                        projection[reactiveName] = true
                        dummyQuerySpec =
                            modelName: @modelClass.name
                            selector: @_id
                            fields: projection
                            limit: 1
                        dummyQsString = J.fetching.stringifyQs dummyQuerySpec
                        J._watchedQuerySpecSet.get()[dummyQsString] = true

                    reactiveValue = @_reactives.tryGet reactiveName

                    # NOTE: Will recompute either if the reactive value doesn't exist,
                    # or if the fetch query that brought up this instance happened to
                    # exclude reactiveName.
                    if reactiveValue is undefined
                        reactiveValue = J.Var(J.denorm.recalc @, reactiveName).get()

                    reactiveValue

                else
                    J.Var(reactiveSpec.val.call @).get()

            else
                if reactiveSpec.denorm and @attached
                    # Record that the current computation uses this denormed reactive

                    projection = _: false
                    projection[reactiveName] = true
                    if Tracker.active
                        # We might be temporarily bumming this field off some other cursor owned
                        # by some other computation, so we need to run fetchOne to update
                        # J.fetching._requestersByQs and make sure the field data doesn't get
                        # pulled away.
                        # While we do want to stop watching this field when the current computation
                        # invalidates, we might *not* need to invalidate the current computation when
                        # the new field data arrives. The reactivity is handled by the @_reactives dict.
                        # Therefore a child J.AutoVar is the perfect place to do the bookkeeping.
                        J.AutoVar(
                            "<#{@modelClass.name} #{@_id}>.reactiveFetcher.#{fieldOrReactiveName}"
                            =>
                                @modelClass.fetchOne @_id,
                                    fields: projection
                            true
                        )

                    @_reactives.get reactiveName

                else
                    # On unattached instances, denormed reactives behave like
                    # non-denormed reactives.
                    J.Var(reactiveSpec.val.call @).get()

        else
            fieldName = fieldOrReactiveName

            if Meteor.isServer and J._watchedQuerySpecSet.get()?
                J.assert @_id?

                # Treat an own-field access the same as any query
                if not @modelClass.immutable
                    projection = _: false
                    projection[fieldName] = true
                    dummyQuerySpec =
                        modelName: @modelClass.name
                        selector: @_id
                        fields: projection
                        limit: 1
                    dummyQsString = J.fetching.stringifyQs dummyQuerySpec
                    J._watchedQuerySpecSet.get()[dummyQsString] = true

                if @_fields.tryGet(fieldName) is undefined
                    console.warn "Field <#{@modelClass.name} #{JSON.stringify @_id}>.#{fieldName}
                        missing from projection"

                    mongoFieldsArg = {}
                    mongoFieldsArg[fieldName] = 1
                    doc = @modelClass.collection.findOne(
                        @_id
                    ,
                        fields: mongoFieldsArg
                        transform: false
                    )
                    value = undefined
                    if doc? then value = doc[fieldName]
                    if value isnt undefined then @_fields.set fieldName, value

            if Tracker.active
                if @_fields.hasKey(fieldName) and @_fields.tryGet(fieldName) is undefined
                    console.warn "<#{@modelClass.name} #{@_id}>.#{fieldName}() is undefined"
                    console.groupCollapsed()
                    console.trace()
                    console.groupEnd()

                if @attached
                    # Record that the current computation uses the current field
                    projection = _: false
                    projection[fieldName] = true
                    if Tracker.active
                        # See the comment for the J.AutoVar in the above if-branch. In this case,
                        # the reactivity for the caller computation is handled by the @_fields dict.
                        J.AutoVar(
                            "<#{@modelClass.name} #{@_id}>.fieldFetcher.#{fieldOrReactiveName}"
                            =>
                                @modelClass.fetchOne @_id,
                                    fields: projection
                            true
                        )

            @_fields.forceGet fieldName


    # ## insert
    # - - -
    # Insert a model document into its collection.
    # - - -
    insert: (options = {}, callback) ->
        if _.isFunction(options) and arguments.length is 1
            callback = options
            options = {}

        @_save false, options, callback


    # ## remove
    # - - -
    # Remove a model document from its collection.
    # - - -
    remove: (callback) ->
        unless @alive
            throw new Meteor.Error "Can't remove dead #{@modelClass.name} instance."

        Meteor.call '_jRemove', @modelClass.name, @_id, callback


    # ## save
    # - - -
    # Save a model instance into its collection.
    # Returns `@_id`.
    # - - -
    save: (options = {}, callback) ->
        if _.isFunction(options) and arguments.length is 1
            callback = options
            options = {}

        @_save true, options, callback


    saveAndDenorm: (options = {}, callback) ->
        if Meteor.isClient
            throw new Error "Can only call saveAndDenorm on the server."

        J.assert 'denormCallback' not of options

        helper = (helperCallback) =>
            options.denormCallback = helperCallback
            @save options, callback

        Meteor.wrapAsync(helper, @)()


    # ## set
    # - - -
    # Set the fields of a model instance.
    # This method takes an dictionary of
    # field names and values.
    #
    #     foo.set
    #       bar: 1
    #       baz: 2
    # - - -
    set: (fields) ->
        unless J.util.isPlainObject fields
            throw new Meteor.Error "Invalid fields setter: #{fields}"

        unless @alive
            throw new Meteor.Error "#{@modelClass.name} ##{@_id} from collection #{@collection} is dead"

        if @attached
            throw new Meteor.Error "Can't set #{@modelClass.name} ##{@_id} because it is attached
                to collection #{J.util.stringify @collection._name}"

        for fieldName, value of fields
            @_fields.set fieldName, J.Var.wrap value, true

        null


    # ## toDoc
    # - - -
    # Reactive.
    # Returns an EJSON object with all the
    # user-defined types serialized into JSON, but
    # not the EJSON primitives (Date and Binary).
    # (A "compound EJSON object" can contain user-defined
    # types in the form of J.Model instances.)
    # - - -
    toDoc: ->

        unless @alive
            throw new Meteor.Error "Can't call toDoc on dead #{@modelClass.name} instance"

        doc = J.Model.toSubdoc @_fields.tryToObj()
        doc._id = @_id
        doc


    # ## toJSONValue
    # - - -
    # Alias for **@toDoc**.  
    # This is used by Meteor EJSON, e.g. EJSON.stringify.  
    # Note that the name is misleading because
    # EJSON's special primitives (Date and Binary)
    # aren't returned as JSON.
    # - - -
    toJSONValue: -> @toDoc()


    # ## toString
    # - - -
    # Returns the string representation of a model instance.
    # - - -
    toString: ->
        if @alive
            Tracker.nonreactive => EJSON.stringify @
        else
            "<#{@modelClass.name} ##{@_id} DEAD>"


    # ## tryGet
    # - - -
    # Try to get a field or reactive value.  
    # If the value is not ready, return `defaultValue`.  
    # - - -
    tryGet: (key, defaultValue) ->
        J.tryGet(
            => @get key
            defaultValue
        )


    # ## typeName
    # - - -
    # Used by Meteor EJSON.
    # - - -
    typeName: ->
        @modelClass.name


    # ## update
    # - - -
    # Update the corresponding model document in `@collection`
    # using MongoDB operators.
    #
    # Calling something like `foo.update(bar: baz)` would replace the entire
    # Mongo doc, which is basically always a mistake. We almost always
    # want to call something like `foo.update($set: bar: baz)` instead.
    # - - -
    update: (args...) ->
        unless @alive
            throw new Meteor.Error "Can't call update on dead #{@modelClass.name} instance"

        unless J.util.isPlainObject(args[0]) and _.all(key[0] is '$' for key of args[0])
            throw new Meteor.Error "Must use a $ operation for #{@modelClass.name}.update"

        @collection.update.bind(@collection, @_id).apply null, args



J.m = J.models = {}


# Queue up all model definitions to help the J
# framework startup sequence. E.g. all models
# must be defined before all components.
modelDefinitionQueue = []


# ## J.defineModel (J.dm)
# - - -
# Define a model. The definition may include
# an `_id`, field declarations under `fields`,
# and reactive definitions under `reactives`.
#
# * `@collection` is the collection that was queried
# to obtain this instance, or the original attached
# clone-ancestor of this instance, or just the
# default place we're going to be inserting/saving to.
#
# * When a model instance is attached, it reactively receives
# changes from its collection and is immutable
# to the application layer.  
# Note that an attached instance always has an `_id.`
#
# * Attached instances die when the collection
# they came from no longer contains their ID.
# They never come back to life, but a new
# attached instance with the same ID may
# eventually replace them in the collection.
# Detached instances dies when their creator
# computation dies, if there is one.
# 
#
#     J.dm 'Foo', 'foos',
#         _id: $$.str
#        
#         fields:
#             a:
#                 type: $$.str
#             b:
#                 type: $$.str
#                 include: false
#             c:
#                 type: $$.str
#        
#         reactives:
#             d:
#                 val: ->
#                     @a() + @c()
#             e:
#                 include: true
#                 val: ->
#                     @b() + 1
#             f:
#                 denorm: true
#                 val: ->
#                     $$.Bar.fetch({ baz: 1 }).count()
# - - -
J.dm = J.defineModel = (modelName, collectionName, members = {}, staticMembers = {}) ->
    modelDefinitionQueue.push
        modelName: modelName
        collectionName: collectionName
        members: members,
        staticMembers: staticMembers


J._defineModel = (modelName, collectionName, members = {}, staticMembers = {}) ->
    modelConstructor = (initFields = {}, @collection = @modelClass.collection) ->
        @_id = initFields._id ? null
        @attached = false
        @alive = true
        if Tracker.active then Tracker.onInvalidate =>
            @alive = false

        nonIdInitFields = _.clone initFields
        delete nonIdInitFields._id

        for fieldName, value of nonIdInitFields
            if fieldName not of @modelClass.fieldSpecs
                throw new Meteor.Error "Invalid field #{JSON.stringify fieldName} passed
                    to #{modelClass.name} constructor"

        @_fields = J.Dict()

        for fieldName, value of nonIdInitFields
            @_fields.setOrAdd fieldName, J.Var.wrap value, true

        if @_id? and @modelClass.idSpec is J.PropTypes.key
            # The fields not specified in the constructor argument should be initialized
            # to the class's default values, but for purposes of checking consistency
            # with the key idSpec, they should be not-ready.
            for fieldName of @modelClass.fieldSpecs
                if fieldName not of nonIdInitFields
                    @_fields.setOrAdd fieldName, J.makeValueNotReadyObject()

            keyReady = false
            try
                # Try calculating the expected value of key but without
                # tracking any client-side or server-side dependencies
                key = Tracker.nonreactive =>
                    if Meteor.isServer and J._watchedQuerySpecSet.get()?
                        J._watchedQuerySpecSet.withValue(
                            null
                            => @key()
                        )
                    else
                        @key()
                keyReady = true
            catch e
                if e not instanceof J.VALUE_NOT_READY
                    console.error e.stack
                    throw e

            if keyReady and @_id isnt key
                console.warn "#{@modelClass.name}._id is #{@_id} but key() is #{key}"

        for fieldName of @modelClass.fieldSpecs
            if fieldName not of nonIdInitFields
                @_fields.setOrAdd fieldName, null # TODO: Support default values for fields of new model instances

        # The @_reactives dict stores the published values of reactives
        # with denorm:true (i.e. server handles all their reactivity).
        @_reactives = J.Dict() # denormedReactiveName: value
        for reactiveName, reactiveSpec of @modelClass.reactiveSpecs
            if reactiveSpec.denorm
                @_reactives.setOrAdd reactiveName, J.makeValueNotReadyObject()

        null

    # Hack to set up the read-only Function.name value
    # for the class. Having the right Function.name is useful
    # for console debugging.
    eval """
        function #{modelName}() {
            return modelConstructor.apply(this, arguments);
        };
        var modelClass = #{modelName};
    """

    _.extend modelClass, J.Model
    _.extend modelClass, staticMembers
    modelClass.collection = null

    memberSpecs = _.clone members
    modelClass.idSpec = memberSpecs._id
    delete memberSpecs._id
    modelClass.immutable = memberSpecs.immutable ? false
    delete memberSpecs.immutable
    modelClass.fieldSpecs = memberSpecs.fields ? {}
    delete memberSpecs.fields
    modelClass.reactiveSpecs = memberSpecs.reactives ? {}
    delete memberSpecs.reactives
    modelClass.indexSpecs = memberSpecs.indexes ? []
    delete memberSpecs.indexes

    modelClass.prototype = new J.Model()
    _.extend modelClass.prototype, memberSpecs
    modelClass.prototype.modelClass = modelClass

    throw new Meteor.Error "#{modelName} missing _id spec" unless modelClass.idSpec?

    fieldAndReactiveSet = {} # fieldOrReactiveName: true
    for fieldName of modelClass.fieldSpecs
        if fieldName is '_id'
            throw new Meteor.Error "_id is not a valid field name for #{modelName}"

        fieldAndReactiveSet[fieldName] = true

    for reactiveName, reactiveSpec of modelClass.reactiveSpecs
        if reactiveName of fieldAndReactiveSet
            throw new Error "Can't have same name for #{modelName} field and reactive:
                #{JSON.stringify reactiveName}"
        if not reactiveSpec.val?
            throw new Meteor.Error "#{modelClass}.reactives.#{reactiveName} missing val function"

        fieldAndReactiveSet[reactiveName] = true

    # Set up @[fieldOrReactiveName] methods for getting/setting fields and getting reactives
    for fieldOrReactiveName of fieldAndReactiveSet
        isReactive = fieldOrReactiveName of modelClass.reactiveSpecs
        spec = modelClass[if isReactive then 'reactiveSpecs' else 'fieldSpecs'][fieldOrReactiveName]

        modelClass.prototype[fieldOrReactiveName] ?= do (fieldOrReactiveName, isReactive, spec) -> (value) ->
            if arguments.length is 0
                # Getter
                @get fieldOrReactiveName
            else
                if isReactive
                    throw new Error "Can't pass arguments to reactive: #{modelClass}.#{fieldOrReactiveName}"
                setter = {}
                setter[fieldOrReactiveName] = value
                @set setter

    # Set up class methods for collection operations
    if collectionName?
        if Meteor.isClient
            # The client has attached instances which power
            # a lot of fancy granular reactivity.

            collection = new Mongo.Collection collectionName,
                transform: (doc) ->
                    J.assert doc._id of collection._attachedInstances
                    collection._attachedInstances[doc._id]

            collection._attachedInstances = {} # _id: instance

            collection.find().observeChanges
                added: (id, fields) ->
                    doc = _.clone fields
                    doc._id = id

                    reactivesObj = doc._reactives
                    delete doc._reactives

                    instance = modelClass.fromDoc doc
                    instance.collection = collection
                    instance.attached = true
                    instance._fields.setReadOnly true, true
                    instance._setReactives reactivesObj ? {}

                    collection._attachedInstances[id] = instance

                changed: (id, fields) ->
                    fields = _.clone fields

                    instance = collection._attachedInstances[id]

                    reactivesObj = fields._reactives
                    delete fields._reactives

                    fieldsSetter = modelClass._getUnescapedSubdoc fields
                    for fieldName, value of fieldsSetter
                        if value is undefined
                            fieldsSetter[fieldName] = J.makeValueNotReadyObject()
                    instance._fields._forceSet fieldsSetter

                    instance._setReactives reactivesObj ? {}

                removed: (id) ->
                    instance = collection._attachedInstances[id]
                    instance.alive = false
                    for reactiveName, reactive of instance.reactives
                        reactive.stop()
                    delete collection._attachedInstances[id]

        if Meteor.isServer
            # The server uses exclusively detached instances
            collection = new Mongo.Collection collectionName,
                transform: (doc) ->
                    reactivesObj = doc._reactives
                    delete doc._reactives
                    instance = modelClass.fromDoc doc
                    instance.collection = collection
                    instance._setReactives reactivesObj ? {}
                    instance

            for indexSpec in modelClass.indexSpecs
                indexFieldsSpec = _.clone indexSpec
                if _.isObject indexSpec.options
                    delete indexFieldsSpec.options
                    indexOptionsSpec = indexSpec.options
                else
                    indexOptionsSpec = {}
                collection._ensureIndex indexFieldsSpec, indexOptionsSpec


        _.extend modelClass,
            collection: collection,
            fetchDict: (docIdsOrQuery, options = {}) ->
                if docIdsOrQuery instanceof J.List or _.isArray docIdsOrQuery
                    if J.List.unwrap(docIdsOrQuery).length is 0
                        return J.Dict()

                query =
                    if docIdsOrQuery instanceof J.List or _.isArray docIdsOrQuery
                        _id: $in: docIdsOrQuery
                    else
                        docIdsOrQuery
                instances = @fetch query, options
                instanceById = J.Dict()
                instances.forEach (instance) ->
                    instanceById.setOrAdd instance._id, instance
                instanceById

            fetchIds: (docIds, options = {}) ->
                instanceDict = @fetchDict docIds, options
                instanceList = J.List()
                for docId in J.List.unwrap docIds
                    if instanceDict.get(docId)?
                        instanceList.push instanceDict.get(docId)
                    else if options.includeHoles
                        instanceList.push null
                instanceList

            fetch: (selector = {}, options = {}) ->
                if Meteor.isClient and not Tracker.active
                    # trick to fetch a model anyway on the client side
                    autoVar = J.AutoVar -> modelClass.fetch selector, options
                    try
                        return autoVar.get()
                    catch e
                        if e instanceof J.VALUE_NOT_READY
                            console.log "Try fetching again."
                            return
                        throw e
                    # throw new Error "On the client, must call #{modelName}.fetch
                    #     from a reactive computation."

                if selector instanceof J.Dict
                    selector = selector.toObj()
                else if J.util.isPlainObject selector
                    selector = J.Dict(selector).toObj()
                options = J.Dict(options).toObj()

                querySpec =
                    modelName: modelName
                    selector: selector
                    fields: options.fields
                    sort: options.sort
                    skip: options.skip
                    limit: options.limit

                if Meteor.isClient
                    J.fetching.requestQuery querySpec

                else
                    qsString = J.fetching.stringifyQs querySpec

                    if J._watchedQuerySpecSet.get()?
                        if not modelClass.immutable
                            J._watchedQuerySpecSet.get()[qsString] = true

                    mongoFieldsArg = J.fetching.projectionToMongoFieldsArg @, options.fields ? {}

                    mongoSelector = J.fetching.selectorToMongoSelector @, selector

                    mongoOptions = _.clone options
                    mongoOptions.fields = mongoFieldsArg

                    instances = J.List @find(mongoSelector, mongoOptions).fetch()

                    # Treat fields that are missing in the Mongo doc (even
                    # though they were included in the query) as having a
                    # default value of null.

                    fieldNameSet = {}
                    for fieldSpec in _.keys mongoFieldsArg
                        fieldName = fieldSpec.split('.')[0]
                        continue if fieldName is '_id'
                        fieldNameSet[fieldName] = true

                    for fieldName of fieldNameSet
                        continue if fieldName is '_reactives'

                        instances.forEach (instance) =>
                            setter = {}

                            # Using instance._fields.tryGet instead of instance.tryGet
                            # because that could update J._watchedQuerySpecSet.
                            if instance._fields.tryGet(fieldName) is undefined
                                setter[fieldName] = null

                            instance.set setter

                    return instances

            fetchOne: (selector = {}, options = {}) ->
                if selector instanceof J.Dict
                    selector = selector.toObj()
                else if J.util.isPlainObject selector
                    selector = J.Dict(selector).toObj()
                options = J.Dict(options).toObj()

                options = _.clone options
                options.limit = 1
                results = @fetch selector, options
                if results is undefined
                    undefined
                else if results.size() is 0
                    # Note that a normal Mongo cursor would
                    # return undefined, but for us null means
                    # "definitely doesn't exist" while undefined
                    # means "fetching in progress".
                    null
                else
                    results.get 0

            find: collection.find.bind collection
            findOne: collection.findOne.bind collection
            insert: (instance, callback) ->
                unless instance instanceof modelClass
                    throw new Meteor.Error "#{@name}.insert requires #{@name} instance."
                instance.insert collection, callback

            update: collection.update.bind collection
            upsert: collection.upsert.bind collection
            remove: collection.remove.bind collection
            tryFetch: (selector = {}, options = {}) ->
                J.tryGet => @fetch selector, options
            tryFetchOne: (selector = {}, options = {}) ->
                J.tryGet => @fetchOne selector, options


    J.models[modelName] = modelClass
    $$[modelName] = modelClass

    EJSON.addType modelName, modelClass.fromJSONValue.bind modelClass



Meteor.methods
    _jSave: (modelName, doc, upsert, options) ->
        # This also runs on the client as a stub

        J.assert doc._id?
        modelClass = J.models[modelName]

        fields = _.clone doc
        delete fields._id

        _reserved = modelName in ['JDataSession']

        if not _reserved
            console.log 'jSave', modelName, doc, @isSimulation

        # TODO: Validation

        if @isSimulation
            modelClass.collection.upsert doc._id,
                $set: fields
            return

        if upsert
            oldDoc = modelClass.findOne(
                doc._id
            ,
                fields:
                    _reactives: 0
                transform: false
            )

            if oldDoc?
                isNew = false
            else
                isNew = true
                oldDoc = {_id: doc._id}

            setter = {}
            for fieldName, newValue of fields
                fieldSpec = modelClass.fieldSpecs[fieldName]

                if newValue isnt undefined
                    oldValue = oldDoc[fieldName]
                    if oldValue isnt undefined and newValue isnt oldValue
                        if modelClass.immutable or fieldSpec.immutable
                            throw new Meteor.Error "Can't save <#{modelName} #{JSON.stringify doc._id}>:
                                Field #{fieldName} is immutable"

                    setter[fieldName] = newValue

            modelClass.collection.upsert doc._id,
                $set: setter

        else
            isNew = true
            oldDoc = {_id: doc._id}
            modelClass.collection.insert doc

        newDoc = J.util.deepClone oldDoc
        for fieldName, newValue of fields
            if newValue isnt undefined
                newDoc[fieldName] = newValue

        instance = modelClass.fromDoc doc

        if not _reserved
            timestamp = new Date()
            if isNew
                # Initialize all the selectable reactives
                for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                    if reactiveSpec.selectable
                        J.denorm.recalc instance, reactiveName, timestamp

            # Note that we won't reset the reactive values we just recalculated
            # because timestamp is the same
            J.denorm.resetWatchers modelName, doc._id, oldDoc, newDoc, timestamp, options.denormCallback

        instance.onSave?()

        doc._id


    _jRemove: (modelName, instanceId) ->
        # This also runs on the client as a stub

        J.assert instanceId?
        modelClass = J.models[modelName]

        _reserved = modelName in ['JDataSession']

        if not _reserved
            console.log 'jRemove', modelName, JSON.stringify(instanceId), @isSimulation

        if @isSimulation
            return modelClass.collection.remove instanceId

        doc = modelClass.findOne(
            instanceId
        ,
            transform: false
        )

        if not doc?
            return 0

        ret = modelClass.collection.remove instanceId

        if not _reserved
            oldFields = _.clone doc
            delete oldFields._reactives
            J.denorm.resetWatchers modelName, instanceId, oldFields, {}

        instance = modelClass.fromDoc doc
        instance.onRemove?()

        ret


Meteor.startup ->
    for modelDef in modelDefinitionQueue
        J._defineModel modelDef.modelName, modelDef.collectionName, modelDef.members, modelDef.staticMembers

    modelDefinitionQueue = null

    if Meteor.isServer
        J.denorm.ensureAllReactiveWatcherIndexes()
