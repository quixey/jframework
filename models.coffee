###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


###
    FIXME:
    1. If modelInstance has some fetched fields but modelInstance.a isn't one of them,
       then calling modelInstance.a() should register a dependency on a query for that
       field. Right now it just throws VALUE_NOT_READY and never does anything about it.

    TODO:
    1. Let fieldSpecs have default values for fields, applicable when using "new"
    2. A special method like modelInstance.isValid() to prevent inserting/updating an
       invalid model
    3. Type system with support for nested data structure schemas
    4. Server-side read/write security specs
    5. The field selector in a query should let you select names of reactives too,
       and make the server compute their value
    6. The field selector in a query should be more like GraphQL, so you can make the
       server follow foreign keys for you without making an extra round trip.
###


class J.Model
    @_getEscapedSubdoc = (subDoc) ->
        if J.util.isPlainObject subDoc
            ret = {}
            for key, value of subDoc
                ret[@escapeDot key] = @_getEscapedSubdoc value
            ret
        else if _.isArray subDoc
            @_getEscapedSubdoc x for x in subDoc
        else
            subDoc


    @_getUnescapedSubdoc = (subDoc) ->
        if J.util.isPlainObject subDoc
            ret = {}
            for key, value of subDoc
                ret[@unescapeDot key] = @_getUnescapedSubdoc value
            ret
        else if _.isArray subDoc
            @_getUnescapedSubdoc x for x in subDoc
        else
            subDoc


    @escapeDot = (key) ->
        key.replace(/\./g, '*DOT*').replace(/\$/g, '*DOLLAR*')


    @fromJSONValue: (jsonValue) ->
        ###
            jsonValue is *not* of the form {$type: ThisModelName, $value: someValue}.
            It's just the someValue part.
        ###

        unless J.util.isPlainObject jsonValue
            throw new Meteor.Error 'Must override J.Model.fromJSONValue to decode non-object values'

        for fieldName, value of jsonValue
            if fieldName[0] is '$'
                throw new Meteor.Error "Bad jsonValue for #{@name}: #{jsonValue}"

        @fromDoc jsonValue


    @fromDoc: (doc) ->
        fields = EJSON.fromJSONValue @_getUnescapedSubdoc doc

        for fieldName of @fieldSpecs
            if fieldName not of fields
                fields[fieldName] = J.makeValueNotReadyObject()

        new @ fields


    @toSubdoc: (x, denormalizeModels = true) ->
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
                value.toDoc denormalizeModels
            else if (
                _.isNumber(value) or _.isBoolean(value) or _.isString(value) or
                    value instanceof Date or value instanceof RegExp or
                    value is null or value is undefined
            )
                value
            else
                throw new Meteor.Error "Unsupported value type: #{value}"

        helper x


    @unescapeDot = (key) =>
        key.replace(/\*DOT\*/g, '.').replace(/\*DOLLAR\*/g, '$')


    clone: ->
        # Nonreactive because the clone's fields are
        # their own new piece of application state.
        doc = Tracker.nonreactive => @toDoc false

        # Note that clones substitute null for undefined.
        for fieldName, value of doc
            if value is undefined
                doc[fieldName] = null

        instance = @modelClass.fromDoc doc
        instance.collection = @collection

        # Note that clones are always detached, alive, and not read-only
        instance


    get: (fieldOrReactiveName) ->
        if not @alive
            throw new Meteor.Error "#{@modelClass.name} ##{@_id} from collection #{@collection} is dead"

        isReactive = fieldOrReactiveName of @modelClass.reactiveSpecs

        if isReactive
            reactiveName = fieldOrReactiveName
            reactiveSpec = @modelClass.reactiveSpecs[fieldOrReactiveName]

            if Meteor.isServer
                J.Var(reactiveSpec.val.call @).get()

            else
                if reactiveSpec.denorm
                    if not @attached
                        throw new Error "Can only get denormed reactive values on attached
                            instances: #{@modelClass.name}.#{fieldOrReactiveName}"

                    # Record that the current computation uses the current reactive
                    projection = {}
                    projection[reactiveName] = 1
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
                    @reactives[reactiveName].get()

        else
            fieldName = fieldOrReactiveName

            if Tracker.active
                if @_fields.hasKey(fieldName) and @_fields.tryGet(fieldName) is undefined
                    console.warn "<#{@modelClass.name} #{@_id}>.#{fieldName}() is undefined"
                    console.groupCollapsed()
                    console.trace()
                    console.groupEnd()

                if @attached
                    # Record that the current computation uses the current field
                    projection = {}
                    projection[fieldName] = 1
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


    insert: (collection = @collection, callback) ->
        if _.isFunction(collection) and arguments.length is 1
            # Can call insert(callback) to use @collection
            # as the collection.
            callback = collection
            collection = @collection

        unless collection instanceof Mongo.Collection
            throw new Meteor.Error "Invalid collection to #{@modelClass.name}.insert"

        if @attached and @collection is collection
            throw new Meteor.Error "Can't insert #{@modelClass.name} instance into its own attached collection"

        unless @alive
            throw new Meteor.Error "Can't insert dead #{@modelClass.name} instance"

        doc = Tracker.nonreactive => @toDoc true
        J.assert J.util.isPlainObject doc
        if not doc._id?
            # The Mongo driver will give us an ID but we
            # can't pass it a null ID.
            delete doc._id

        # Returns @_id
        @_id = collection.insert doc, callback


    remove: (callback) ->
        unless @alive
            throw new Meteor.Error "Can't remove dead #{@modelClass.name} instance."

        Meteor.call '_jRemove', @modelClass.name, @_id, callback


    save: (collection = @collection, callback) ->
        if _.isFunction(collection) and arguments.length is 1
            # Can call save(callback) to use @collection
            # as the collection.
            callback = collection
            collection = @collection

        unless collection instanceof Mongo.Collection
            throw new Meteor.Error "Invalid collection to #{@modelClass.name}.insert"

        if @attached and @collection is collection
            throw new Meteor.Error "Can't save #{@modelClass.name} instance into its own attached collection"

        unless @alive
            throw new Meteor.Error "Can't save dead #{@modelClass.name} instance"

        doc = Tracker.nonreactive => @toDoc(true)

        doc._id ?= Random.hexString(10)

        Meteor.call '_jSave', @modelClass.name, doc, callback

        # Returns @_id
        @_id ?= doc._id


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


    toDoc: (denormalize = false) ->
        # Reactive.
        # Returns an EJSON object with all the
        # user-defined types serialized into JSON, but
        # not the EJSON primitives (Date and Binary).
        # (A "compound EJSON object" can contain user-defined
        # types in the form of J.Model instances.)

        unless @alive
            throw new Meteor.Error "Can't call toDoc on dead #{@modelClass.name} instance"

        doc = J.Model.toSubdoc(@_fields.tryToObj(), denormalize)

        if denormalize and @modelClass.idSpec is J.PropTypes.key
            key = @key() # Might throw a legitimate VALUE_NOT_READY
            J.assert key? and (@_id is key or not @_id?)
            doc._id = key
        else
            doc._id = @_id

        doc


    toJSONValue: ->
        ###
            Used by Meteor EJSON, e.g. EJSON.stringify.
            Note that the name is misleading because
            EJSON's special primitives (Date and Binary)
            aren't returned as JSON.
        ###

        @toDoc false


    toString: ->
        if @alive
            Tracker.nonreactive => EJSON.stringify @
        else
            "<#{@modelClass.name} ##{@_id} DEAD>"


    tryGet: (key, defaultValue) ->
        J.tryGet(
            => @get key
            defaultValue
        )


    typeName: ->
        ### Used by Meteor EJSON ###
        @modelClass.name


    update: (args...) ->
        unless @alive
            throw new Meteor.Error "Can't call update on dead #{@modelClass.name} instance"

        unless J.util.isPlainObject(args[0]) and _.all(key[0] is '$' for key of args[0])
            # Calling something like .update(foo: bar) would replace the entire
            # Mongo doc, which is basically always a mistake. We almost always
            # want to call something like .update($set: foo: bar) instead.
            throw new Meteor.Error "Must use a $ operation for #{@modelClass.name}.update"

        @collection.update.bind(@collection, @_id).apply null, args



J.m = J.models = {}


# Queue up all model definitions to help the J
# framework startup sequence. E.g. all models
# must be defined before all components.
modelDefinitionQueue = []

J.dm = J.defineModel = (modelName, collectionName, members = {}, staticMembers = {}) ->
    modelDefinitionQueue.push
        modelName: modelName
        collectionName: collectionName
        members: members,
        staticMembers: staticMembers


J._defineModel = (modelName, collectionName, members = {}, staticMembers = {}) ->
    modelConstructor = (initFields = {}, @collection = @modelClass.collection) ->
        @_id = initFields._id ? null

        # @collection is the collection that was queried
        # to obtain this instance, or the original attached
        # clone-ancestor of this instance, or just the
        # default place we're going to be inserting/saving to.

        # If true, this instance reactively receives
        # changes from its collection and is immutable
        # to the application layer.
        # Note that an attached instance always has an _id.
        @attached = false

        # Attached instances die when the collection
        # they came from no longer contains their ID.
        # They never come back to life, but a new
        # attached instance with the same ID may
        # eventually replace them in the collection.
        # Detached instances dies when their creator
        # computation dies, if there is one.
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

        for fieldName of @modelClass.fieldSpecs
            @_fields.setOrAdd fieldName, null
        for fieldName, value of nonIdInitFields
            @_fields.set fieldName, J.Var.wrap value, true

        if @_id? and @modelClass.idSpec is J.PropTypes.key
            keyReady = false
            try
                key = Tracker.nonreactive => @key()
                keyReady = true
            catch e
                throw e if e not instanceof J.VALUE_NOT_READY

            if keyReady and @_id isnt key
                console.warn "#{@modelClass.name}._id is #{@_id} but key() is #{key}"

        @reactives = {} # reactiveName: autoVar
        for reactiveName, reactiveSpec of @modelClass.reactiveSpecs
            @reactives[reactiveName] = do (reactiveName, reactiveSpec) =>
                J.AutoVar "<#{modelName} ##{@_id}>.!#{reactiveName}",
                    => reactiveSpec.val.call @

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

                    # The @_reactives dict stores the published values of reactives
                    # with denorm:true (i.e. server handles all their reactivity).
                    instance._reactives = J.Dict() # denormedReactiveName: value
                    for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                        if reactiveSpec.denorm
                            instance._reactives.setOrAdd reactiveName, J.makeValueNotReadyObject()

                    if reactivesObj?
                        reactivesSetter = {}

                        for reactiveName, reactiveObj of reactivesObj
                            reactivesSetter[reactiveName] = modelClass._getUnescapedSubdoc reactiveObj.val
                            if reactivesSetter[reactiveName] is undefined
                                reactivesSetter[reactiveName] = J.makeValueNotReadyObject()

                        instance._reactives.set reactivesSetter

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

                    if reactivesObj?
                        reactivesSetter = {}

                        for reactiveName, reactiveSpec of modelClass.reactiveSpecs
                            if reactiveSpec.denorm
                                if reactiveName of reactivesObj
                                    reactivesSetter[reactiveName] =
                                        modelClass._getUnescapedSubdoc reactivesObj[reactiveName].val
                                if reactivesSetter[reactiveName] is undefined
                                    reactivesSetter[reactiveName] = J.makeValueNotReadyObject()

                        instance._reactives._forceSet reactivesSetter

                removed: (id) ->
                    instance = collection._attachedInstances[id]
                    instance.alive = false
                    for reactiveName, reactive of instance.reactives
                        reactive.stop()
                    delete collection._attachedInstances[id]

        if Meteor.isServer
            # The server uses exclusively detached instances and
            # doesn't make use of much reactivity.
            collection = new Mongo.Collection collectionName,
                transform: (doc) ->
                    doc = _.clone doc

                    reactivesObj = modelClass._getUnescapedSubdoc doc._reactives
                    if reactivesObj?
                        console.warn "No reason for the server-side ORM to ever
                            fetch the _reactives field."
                    delete doc._reactives

                    instance = modelClass.fromDoc doc
                    instance.collection = collection

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
            fetchDict: (docIdsOrQuery) ->
                if docIdsOrQuery instanceof J.List or _.isArray docIdsOrQuery
                    if J.List.unwrap(docIdsOrQuery).length is 0
                        return J.Dict()

                query =
                    if docIdsOrQuery instanceof J.List or _.isArray docIdsOrQuery
                        _id: $in: docIdsOrQuery
                    else
                        docIdsOrQuery
                instances = @fetch query
                instanceById = J.Dict()
                instances.forEach (instance) ->
                    instanceById.setOrAdd instance._id, instance
                instanceById

            fetchIds: (docIds, includeHoles = false) ->
                instanceDict = @fetchDict docIds
                instanceList = J.List()
                for docId in J.List.unwrap docIds
                    if instanceDict.get(docId)?
                        instanceList.push instanceDict.get(docId)
                    else if includeHoles
                        instanceList.push null
                instanceList

            fetch: (selector = {}, options = {}) ->
                if Meteor.isClient and not Tracker.active
                    throw new Error "On the client, must call #{modelName}.fetch
                        from a reactive computation."

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

                if Meteor.isServer
                    qsString = EJSON.stringify querySpec

                    if J._watchedQuerySpecSet.get()?
                        J._watchedQuerySpecSet.get()[qsString] = true

                    instances = J.List @find(selector, options).fetch()

                    if not options.fields?
                        # Treat fields that are missing in the Mongo doc as
                        # having a default value of null.
                        instances.forEach (instance) =>
                            setter = {}
                            for fieldName of @fieldSpecs
                                if instance.tryGet(fieldName) is undefined
                                    setter[fieldName] = null
                            instance.set setter

                    return instances

                J.fetching.requestQuery querySpec

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
    _jSave: (modelName, doc) ->
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

        oldDoc = modelClass.findOne(
            doc._id
        ,
            fields:
                _reactives: 0
            transform: false
        )

        setter = {}
        newDoc = EJSON.parse EJSON.stringify oldDoc ? {_id: doc._id}
        for fieldName, newValue of fields
            if newValue isnt undefined
                setter[fieldName] = newValue
                newDoc[fieldName] = newValue

        modelClass.collection.upsert doc._id,
            $set: setter

        if not _reserved
            J.denorm.resetWatchers modelName, doc._id, oldDoc ? {_id: doc._id}, newDoc

        doc._id

    _jRemove: (modelName, instanceId, oldDoc = null) ->
        # This also runs on the client as a stub

        J.assert instanceId?
        modelClass = J.models[modelName]

        _reserved = modelName in ['JDataSession']

        if not _reserved
            console.log 'jRemove', modelName, instanceId, @isSimulation

        if @isSimulation
            modelClass.collection.remove instanceId
            return

        if not oldDoc?
            oldDoc = modelClass.findOne(
                instanceId
            ,
                fields:
                    _reactives: 0
                transform: false
            )

        ret = modelClass.collection.remove instanceId

        if not _reserved
            J.denorm.resetWatchers modelName, instanceId, oldDoc, {}

        ret


Meteor.startup ->
    for modelDef in modelDefinitionQueue
        J._defineModel modelDef.modelName, modelDef.collectionName, modelDef.members, modelDef.staticMembers

    modelDefinitionQueue = null

    if Meteor.isServer
        J.denorm.ensureAllReactiveWatcherIndexes()
