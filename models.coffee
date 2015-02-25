###
  TODO:
  * Each fieldspec should be declared with type, default value (optional) and docstring (optional)
  * isValid() function so we can't insert/update an invalid model
  * key() function which either returns _id or is computed from other fields
    with a field type system to have a special value to indicate when _id is computed,
    like a "key" type for the _id, as opposed to being its own entropy.
    It's saying whether "_id" is part of the Normalized Kernel.

  *
    fetch and fetchOne - like find and findOne
        * Acts like a Reactive, throwing a notReadyError
        * Supports
        * Being ready means
            * More info from the server wouldn't change the query result
        * fetchOne returns null (not undefined) meaning "Doesn't currently exist on source"
        * Return Lists
        * Supports recursive "fields"

  *
    Model instance field getters like .name():
        If this is an attached instance, treat it like a Reactive's get
            whose val is -> @fetchOne(@_id, fields: name: true)
        Otherwise naively return the value, even if it's undefined, like a tryGet.

  *
    Each field can have a default include: true/false


Notes about the difference between reactives and normal functions:
    * Reactives should be pure functions of the database and the current time
        * No outside inputs - not the current user's ID or the current UI state
        * Time is okay because we want to allow stuff like User.latestPosts
        * That means the only notReadyError should be ultimately propagated
          from a fetch call somewhere in the AutoVar stack. No not-ready external calls.
    * When a normal function throws a notReady error, the system knows to fetch
      any non-ready fetch objects that were instantiated during the partially-run
      code. When a J.Model Reactive throws a notReady error, the system also
      knows to @modelClass.fetchOne @_id, fields: reactiveName: true
      i.e. anticipate all data in that reactive.
    * Reactives can have include: true, or even include: {name: true, posts: {votes: true}},
      just like fields.
###


class J.Model
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
        fields = EJSON.fromJSONValue doc

        for fieldName of @fieldSpecs
            if fieldName not of fields
                fields[fieldName] = J.makeValueNotReadyObject()

        new @ fields


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


    get: (fieldName) ->
        if not @alive
            throw new Meteor.Error "#{@modelClass.name} ##{@_id} from collection #{@collection} is dead"

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

        @collection.remove @_id, callback


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

        doc = Tracker.nonreactive => @toDoc true
        J.assert J.util.isPlainObject doc

        if doc._id?
            @_id = doc._id
            fields = _.clone doc
            delete fields._id
            collection.upsert @_id,
                $set: fields,
                callback
        else
            # The Mongo driver will give us an ID but we
            # can't pass it a null ID
            delete doc._id
            @_id = collection.insert doc, callback

        @_id


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

        toPrimitiveEjsonObj = (value) =>
            if _.isArray(value)
                (toPrimitiveEjsonObj v for v in value)
            else if J.util.isPlainObject(value)
                ret = {}
                for k, v of value
                    ret[k] = toPrimitiveEjsonObj v
                ret
            else if value instanceof J.Model
                value.toDoc denormalize
            else if (
                _.isNumber(value) or _.isBoolean(value) or _.isString(value) or
                value instanceof Date or value instanceof RegExp or
                value is null or value is undefined
            )
                value
            else
                throw new Meteor.Error "Unsupported value type: #{value}"

        doc = toPrimitiveEjsonObj @_fields.toObj()

        if denormalize and @modelClass.idSpec is J.PropTypes.key
            key = @key()
            J.assert not @_id? or @_id is key
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
        # Detached instances are always alive.
        @alive = true

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
            unless @_id is @key()
                console.warn "#{@modelClass.name}._id is #{@_id} but key() is #{@key()}"

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
    modelClass.fieldSpecs = memberSpecs.fields
    delete memberSpecs.fields
    modelClass.reactiveSpecs = memberSpecs.reactives
    delete memberSpecs.reactives

    modelClass.prototype = new J.Model()
    _.extend modelClass.prototype, memberSpecs
    modelClass.prototype.modelClass = modelClass

    throw new Meteor.Error "#{modelName} missing _id spec" unless modelClass.idSpec?

    # Set up instance methods for getting/setting fields
    for fieldName, fieldSpec of modelClass.fieldSpecs
        if fieldName is '_id'
            throw new Meteor.Error "_id is not a valid field name for #{modelName}"

        modelClass.prototype[fieldName] ?= do (fieldName, fieldSpec) -> (value) ->
            if arguments.length is 0
                # Getter
                @get fieldName
            else
                setter = {}
                setter[fieldName] = value
                @set setter

    # Set up reactives
    for reactiveName, reactiveSpec of modelClass.reactiveSpecs
        if reactiveName of modelClass.fieldSpecs
            throw new Meteor.Error "#{modelClass}.reactive can't have same name as field: #{reactiveName}"

        unless reactiveSpec.val?
            throw new Meteor.Error "#{modelClass}.reactives.#{reactiveName} missing val function"

        modelClass.prototype[reactiveName] ?= do (reactiveName, reactiveSpec) -> ->
            @reactives[reactiveName].get()



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
                    instance = modelClass.fromDoc doc
                    instance.collection = collection
                    instance.attached = true
                    instance._fields.setReadOnly true, true
                    collection._attachedInstances[id] = instance

                changed: (id, fields) ->
                    instance = collection._attachedInstances[id]
                    instance._fields._forceSet fields

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
                    instance = modelClass.fromDoc doc
                    instance.collection = collection
                    instance


        _.extend modelClass,
            collection: collection,
            fetchDict: (docIdsOrQuery) ->
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
                for docId in docIds
                    if instanceDict.get(docId)?
                        instanceList.push instanceDict.get(docId)
                    else if includeHoles
                        instanceList.push null
                instanceList

            fetch: (selector = {}, options = {}) ->
                if selector instanceof J.Dict
                    selector = selector.toObj()
                else if J.util.isPlainObject selector
                    selector = J.Dict(selector).toObj()
                options = J.Dict(options).toObj()

                if Meteor.isServer
                    return J.List @find(selector, options).fetch()

                querySpec =
                    modelName: modelName
                    selector: selector
                    fields: options.fields
                    sort: options.sort
                    skip: options.skip
                    limit: options.limit

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


Meteor.startup ->
    for modelDef in modelDefinitionQueue
        J._defineModel modelDef.modelName, modelDef.collectionName, modelDef.members, modelDef.staticMembers

    modelDefinitionQueue = null